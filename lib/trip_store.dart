import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'validators.dart';

typedef PreferencesFactory = Future<SharedPreferences> Function();

class TripStore {
  TripStore({PreferencesFactory? preferencesFactory})
      : _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance;

  static const int schemaVersion = 2;
  static const String dataKey = 'appDataV2';
  static const String pendingKey = 'appDataV2Pending';
  static const String intermediateTripsKey = 'trips_json';
  static const String intermediatePrefectureStatesKey =
      'prefecture_states_json';
  static const String legacyTripsKey = 'trips';
  static const String legacyPrefectureStatesKey = 'prefectureStates';

  final PreferencesFactory _preferencesFactory;

  Future<AppData> load() async {
    final preferences = await _preferencesFactory();

    final pending = preferences.getString(pendingKey);
    if (pending != null) {
      try {
        final recovered = _decode(pending);
        await _writeNormalizedAppData(preferences, recovered);
        return recovered;
      } on FormatException {
        await preferences.remove(pendingKey);
      }
    }

    final stored = preferences.getString(dataKey);
    if (stored != null) {
      final recovered = _decode(stored);
      await _writeNormalizedAppData(preferences, recovered);
      return recovered;
    }

    final migrated = _loadIntermediate(preferences) ?? _loadLegacy(preferences);
    await save(migrated);
    await preferences.remove(intermediateTripsKey);
    await preferences.remove(intermediatePrefectureStatesKey);
    await preferences.remove(legacyTripsKey);
    await preferences.remove(legacyPrefectureStatesKey);
    return migrated;
  }

  Future<void> _writeNormalizedAppData(
    SharedPreferences preferences,
    AppData data,
  ) async {
    final encoded = jsonEncode(_encode(data));
    final written = await preferences.setString(dataKey, encoded);
    if (!written) {
      throw FileSystemException('保存データを書き込めませんでした');
    }
    await preferences.remove(pendingKey);
  }

  Future<void> save(AppData data) async {
    final preferences = await _preferencesFactory();
    final encoded = jsonEncode(_encode(data));

    final pendingWritten = await preferences.setString(pendingKey, encoded);
    if (!pendingWritten) {
      throw FileSystemException('保存準備データを書き込めませんでした');
    }

    await _writeCanonical(preferences, encoded);
  }

  Future<void> _writeCanonical(
    SharedPreferences preferences,
    String encoded,
  ) async {
    final written = await preferences.setString(dataKey, encoded);
    if (!written) {
      throw FileSystemException('保存データを書き込めませんでした');
    }
    await preferences.remove(pendingKey);
  }

  AppData _decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('保存データを読み取れません: $error');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('保存データの形式が正しくありません');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('対応していない保存データ形式です');
    }

    final claimedPaths = <String>{};
    final seenTripIds = <String>{};
    final tripsValue = decoded['trips'];
    if (tripsValue is! List) {
      throw const FormatException('旅行データがありません');
    }

    final trips = <Trip>[];
    for (final value in tripsValue) {
      if (value is! Map) {
        continue;
      }
      final record = Map<String, dynamic>.from(value);
      final title = record['title'];
      if (title is! String) {
        continue;
      }
      final normalizedTitle = normalizeTripTitle(title);
      if (normalizedTitle == null) {
        continue;
      }
      var id = record['id'];
      if (id is! String || id.isEmpty || seenTripIds.contains(id)) {
        id = createEntityId('trip');
      }
      seenTripIds.add(id);
      trips.add(
        Trip(
          id: id,
          title: normalizedTitle,
          photos: _readExistingUniqueFiles(
            record['photos'],
            claimedPaths,
          ),
        ),
      );
    }

    final prefectureStatesValue = decoded['prefectureStates'];
    final prefectureStates = <String, String>{};
    if (prefectureStatesValue is Map) {
      for (final entry in prefectureStatesValue.entries) {
        if (entry.key is String && entry.value is String) {
          prefectureStates[entry.key as String] = entry.value as String;
        }
      }
    }

    return AppData(
      trips: trips,
      unassignedPhotos: _readExistingUniqueFiles(
        decoded['unassignedPhotos'],
        claimedPaths,
      ),
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }

  Map<String, Object> _encode(AppData data) {
    final claimedPaths = <String>{};

    List<String> encodeFiles(Iterable<File> files) {
      final paths = <String>[];
      for (final file in files) {
        final path = file.path;
        if (!claimedPaths.add(path)) {
          throw StateError('同じ写真が複数の旅行に所属しています: $path');
        }
        paths.add(path);
      }
      return paths;
    }

    final prefectureStates = <String, String>{};
    for (final entry in data.prefectureStates.entries) {
      if (entry.value != 'unvisited') {
        prefectureStates[entry.key] = entry.value;
      }
    }

    return <String, Object>{
      'schemaVersion': schemaVersion,
      'trips': data.trips
          .map(
            (trip) => <String, Object>{
              'id': trip.id,
              'title': trip.title,
              'photos': encodeFiles(trip.photos),
            },
          )
          .toList(growable: false),
      'unassignedPhotos': encodeFiles(data.unassignedPhotos),
      'prefectureStates': prefectureStates,
    };
  }

  AppData? _loadIntermediate(SharedPreferences preferences) {
    final tripsRaw = preferences.getString(intermediateTripsKey);
    final statesRaw = preferences.getString(intermediatePrefectureStatesKey);
    if (tripsRaw == null && statesRaw == null) return null;

    final trips = <Trip>[];
    final claimedPaths = <String>{};
    if (tripsRaw != null) {
      final decoded = jsonDecode(tripsRaw);
      if (decoded is! List) {
        throw const FormatException('移行元の旅行データが壊れています');
      }
      for (final value in decoded) {
        if (value is! Map) {
          continue;
        }
        final record = Map<String, dynamic>.from(value);
        final title = record['title'];
        if (title is! String) {
          continue;
        }
        final normalizedTitle = normalizeTripTitle(title);
        if (normalizedTitle == null) {
          continue;
        }
        trips.add(
          Trip(
            id: createEntityId('trip'),
            title: normalizedTitle,
            photos: _readExistingUniqueFiles(
              record['photos'],
              claimedPaths,
            ),
          ),
        );
      }
    }

    final prefectureStates = <String, String>{};
    if (statesRaw != null) {
      final decoded = jsonDecode(statesRaw);
      if (decoded is! Map) {
        throw const FormatException('移行元の都道府県データが壊れています');
      }
      for (final entry in decoded.entries) {
        if (entry.key is String && entry.value is String) {
          prefectureStates[entry.key as String] = entry.value as String;
        }
      }
    }

    return AppData(
      trips: trips,
      unassignedPhotos: const <File>[],
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }

  AppData _loadLegacy(SharedPreferences preferences) {
    final trips = <Trip>[];
    final claimedPaths = <String>{};
    for (final record
        in preferences.getStringList(legacyTripsKey) ?? const <String>[]) {
      final separator = record.indexOf('|');
      if (separator <= 0) continue;
      final title = record.substring(0, separator);
      final normalizedTitle = normalizeTripTitle(title);
      if (normalizedTitle == null) continue;
      final photos = record
          .substring(separator + 1)
          .split(';;')
          .where((path) => path.isNotEmpty)
          .where(claimedPaths.add)
          .map(File.new)
          .where((file) => file.existsSync())
          .toList(growable: false);
      trips.add(
        Trip(
          id: createEntityId('trip'),
          title: normalizedTitle,
          photos: photos,
        ),
      );
    }

    final prefectureStates = <String, String>{};
    for (final value in preferences.getStringList(
          legacyPrefectureStatesKey,
        ) ??
        const <String>[]) {
      final separator = value.indexOf('|');
      if (separator > 0) {
        prefectureStates[value.substring(0, separator)] =
            value.substring(separator + 1);
      }
    }

    return AppData(
      trips: trips,
      unassignedPhotos: const <File>[],
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }

  List<File> _readExistingUniqueFiles(
    Object? value,
    Set<String> claimedPaths,
  ) {
    if (value == null) return const <File>[];
    if (value is! List) {
      throw const FormatException('写真データが壊れています');
    }

    final files = <File>[];
    for (final path in value) {
      if (path is! String) {
        throw const FormatException('写真パスが壊れています');
      }
      if (!claimedPaths.add(path)) continue;
      final file = File(path);
      if (file.existsSync()) files.add(file);
    }
    return files;
  }
}
