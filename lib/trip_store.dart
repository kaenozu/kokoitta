import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'photo.dart';
import 'validators.dart';

typedef PreferencesFactory = Future<SharedPreferences> Function();

class TripStore {
  TripStore({PreferencesFactory? preferencesFactory})
    : _preferencesFactory = preferencesFactory ?? SharedPreferences.getInstance;

  /// v3: photos are `{id, path, capturedAt?, location?, originalName?,
  /// mimeType?}` records. v2（path文字列のリスト）は読み込み時に無損失で移行する。
  /// キー名は既存端末のデータを失わないためv2のまま維持する。
  static const int schemaVersion = 3;
  static const int legacySchemaVersion = 2;
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
        final canonical = _canonicalize(recovered);
        final encoded = jsonEncode(_encode(canonical));
        await _writeCanonical(preferences, encoded);
        return recovered;
      } on FormatException {
        await preferences.remove(pendingKey);
      }
    }

    final stored = preferences.getString(dataKey);
    if (stored != null) {
      final recovered = _decode(stored);
      final canonical = _canonicalize(recovered);
      final canonicalEncoded = jsonEncode(_encode(canonical));
      if (canonicalEncoded != stored) {
        final written = await preferences.setString(dataKey, canonicalEncoded);
        if (!written) {
          throw FileSystemException('保存データを書き込めませんでした');
        }
      }
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

  Future<void> save(AppData data) async {
    final preferences = await _preferencesFactory();
    final canonical = _canonicalize(data);
    final encoded = jsonEncode(_encode(canonical));

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

  /// 旧形式（v1/intermediate/v2）の写真へ付与する決定的ID。
  ///
  /// 正規化したファイルパスのSHA-256先頭32桁を使用するため、同じ旧データを
  /// 再migrationしても同じIDになる。パスをそのままIDにはせず、復元や移動で
  /// パスが変わっても保存済みIDは維持される。
  static String legacyPhotoId(String path) {
    final normalized = path.replaceAll('\\', '/');
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return 'photo-${digest.substring(0, 32)}';
  }

  AppData _canonicalize(AppData data) {
    final trips = <Trip>[];
    var unassignedPhotos = <Photo>[...data.unassignedPhotos];

    for (final trip in data.trips) {
      final normalizedTitle = normalizeTripTitle(trip.title);
      if (normalizedTitle == null) {
        unassignedPhotos = [...unassignedPhotos, ...trip.photos];
        continue;
      }
      trips.add(Trip(id: trip.id, title: normalizedTitle, photos: trip.photos));
    }

    return AppData(
      trips: trips,
      unassignedPhotos: unassignedPhotos,
      prefectureStates: normalizePrefectureStates(data.prefectureStates),
    );
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
    final version = decoded['schemaVersion'];
    if (version == schemaVersion) return _decodeV3(decoded);
    if (version == legacySchemaVersion) return _decodeV2(decoded);
    throw const FormatException('対応していない保存データ形式です');
  }

  /// 無効タイトルの旅行に含まれる写真を救済するための共通ヘルパー。
  ///
  /// 写真の読み取り順は次の優先順位で決定的にする。
  ///
  /// 1. 有効タイトルの旅行に所属する写真（先にclaim）
  /// 2. 既存の旅行未設定写真（次にclaim）
  /// 3. 無効タイトルの旅行から救済する写真（最後にclaim、重複は破棄）
  ///
  /// 写真一覧が構造的に読めない場合（Listでない、要素がMapでない、
  /// id・pathが不正）は既存のfail-closed方針どおりFormatExceptionを
  /// 投げ、存在しない写真を推測して生成しない。ファイルが存在しない
  /// 写真は従来どおり読み飛ばす。
  List<Photo> _readAndRecover(
    List<Object?> photosValues,
    Set<String> claimedPaths,
    Set<String> claimedIds,
    bool legacy,
  ) {
    final recovered = <Photo>[];
    for (final photosValue in photosValues) {
      recovered.addAll(
        legacy
            ? _readLegacyFiles(photosValue, claimedPaths)
            : _readPhotos(photosValue, claimedPaths, claimedIds),
      );
    }
    return recovered;
  }

  AppData _decodeV2(Map<String, dynamic> decoded) {
    final claimedPaths = <String>{};
    final seenTripIds = <String>{};
    final tripsValue = decoded['trips'];
    if (tripsValue is! List) {
      throw const FormatException('旅行データがありません');
    }

    // タイトルの妥当性と写真一覧の妥当性を独立に評価する。
    // タイトルが無効な旅行でも、構造的に読める写真は旅行未設定へ救済する。
    final invalidPhotoValues = <Object?>[];
    final trips = <Trip>[];
    for (final value in tripsValue) {
      if (value is! Map) {
        continue;
      }
      final record = Map<String, dynamic>.from(value);
      final title = record['title'];
      if (title is! String) {
        invalidPhotoValues.add(record['photos']);
        continue;
      }
      final normalizedTitle = normalizeTripTitle(title);
      if (normalizedTitle == null) {
        invalidPhotoValues.add(record['photos']);
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
          photos: _readLegacyFiles(record['photos'], claimedPaths),
        ),
      );
    }

    final unassignedPhotos = _readLegacyFiles(
      decoded['unassignedPhotos'],
      claimedPaths,
    );
    final recoveredPhotos = _readAndRecover(
      invalidPhotoValues,
      claimedPaths,
      const <String>{},
      true,
    );

    final prefectureStates = _readPrefectureStates(decoded['prefectureStates']);
    return AppData(
      trips: trips,
      unassignedPhotos: <Photo>[...unassignedPhotos, ...recoveredPhotos],
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }

  AppData _decodeV3(Map<String, dynamic> decoded) {
    final claimedPaths = <String>{};
    final claimedIds = <String>{};
    final seenTripIds = <String>{};
    final tripsValue = decoded['trips'];
    if (tripsValue is! List) {
      throw const FormatException('旅行データがありません');
    }

    final invalidPhotoValues = <Object?>[];
    final trips = <Trip>[];
    for (final value in tripsValue) {
      if (value is! Map) {
        continue;
      }
      final record = Map<String, dynamic>.from(value);
      final title = record['title'];
      if (title is! String) {
        invalidPhotoValues.add(record['photos']);
        continue;
      }
      final normalizedTitle = normalizeTripTitle(title);
      if (normalizedTitle == null) {
        invalidPhotoValues.add(record['photos']);
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
          photos: _readPhotos(record['photos'], claimedPaths, claimedIds),
        ),
      );
    }

    final unassignedPhotos = _readPhotos(
      decoded['unassignedPhotos'],
      claimedPaths,
      claimedIds,
    );
    final recoveredPhotos = _readAndRecover(
      invalidPhotoValues,
      claimedPaths,
      claimedIds,
      false,
    );

    final prefectureStates = _readPrefectureStates(decoded['prefectureStates']);
    return AppData(
      trips: trips,
      unassignedPhotos: <Photo>[...unassignedPhotos, ...recoveredPhotos],
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }

  Map<String, Object> _encode(AppData data) {
    final claimedPaths = <String>{};
    final claimedIds = <String>{};

    List<Map<String, Object>> encodePhotos(Iterable<Photo> photos) {
      final records = <Map<String, Object>>[];
      for (final photo in photos) {
        if (!claimedIds.add(photo.id)) {
          throw StateError('同じ写真IDが複数箇所に所属しています: ${photo.id}');
        }
        if (!claimedPaths.add(photo.file.path)) {
          throw StateError('同じ写真が複数の旅行に所属しています: ${photo.file.path}');
        }
        records.add(_encodePhoto(photo));
      }
      return records;
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
              'photos': encodePhotos(trip.photos),
            },
          )
          .toList(growable: false),
      'unassignedPhotos': encodePhotos(data.unassignedPhotos),
      'prefectureStates': prefectureStates,
    };
  }

  static Map<String, Object> _encodePhoto(Photo photo) {
    final record = <String, Object>{'id': photo.id, 'path': photo.file.path};
    final capturedAt = photo.capturedAt;
    if (capturedAt != null) {
      record['capturedAt'] = capturedAt.toIso8601String();
    }
    if (photo.location != null) record['location'] = photo.location!;
    if (photo.originalName != null) {
      record['originalName'] = photo.originalName!;
    }
    if (photo.mimeType != null) record['mimeType'] = photo.mimeType!;
    return record;
  }

  /// v2形式の写真（パス文字列）を読む。欠損ファイルは従来どおり無視する。
  List<Photo> _readLegacyFiles(Object? value, Set<String> claimedPaths) {
    if (value == null) return const <Photo>[];
    if (value is! List) {
      throw const FormatException('写真データが壊れています');
    }

    final photos = <Photo>[];
    for (final path in value) {
      if (path is! String) {
        throw const FormatException('写真パスが壊れています');
      }
      if (!claimedPaths.add(path.replaceAll('\\', '/'))) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      photos.add(Photo(id: legacyPhotoId(path), file: file));
    }
    return photos;
  }

  /// v3形式の写真レコードを読む。パス・IDの重複は読み込み時に最初の1件へ
  /// 集約し、欠損ファイルは無視する。metadataは壊れていてもnullへ正規化する。
  List<Photo> _readPhotos(
    Object? value,
    Set<String> claimedPaths,
    Set<String> claimedIds,
  ) {
    if (value == null) return const <Photo>[];
    if (value is! List) {
      throw const FormatException('写真データが壊れています');
    }

    final photos = <Photo>[];
    for (final item in value) {
      if (item is! Map) {
        throw const FormatException('写真データが壊れています');
      }
      final record = Map<String, dynamic>.from(item);
      final id = record['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('写真IDが壊れています');
      }
      final path = record['path'];
      if (path is! String) {
        throw const FormatException('写真パスが壊れています');
      }
      // セパレータ表記違い（\ と /）は正規化して同一パスとして扱う。
      final normalizedPath = path.replaceAll('\\', '/');
      if (claimedPaths.contains(normalizedPath) || claimedIds.contains(id)) {
        continue;
      }
      claimedPaths.add(normalizedPath);
      claimedIds.add(id);
      final file = File(path);
      if (!file.existsSync()) continue;
      photos.add(
        Photo(
          id: id,
          file: file,
          capturedAt: _readCapturedAt(record['capturedAt']),
          location: _readOptionalString(record['location']),
          originalName: _readOptionalString(record['originalName']),
          mimeType: _readOptionalString(record['mimeType']),
        ),
      );
    }
    return photos;
  }

  static DateTime? _readCapturedAt(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static String? _readOptionalString(Object? value) {
    return value is String ? value : null;
  }

  static Map<String, String> _readPrefectureStates(Object? value) {
    final prefectureStates = <String, String>{};
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String && entry.value is String) {
          prefectureStates[entry.key as String] = entry.value as String;
        }
      }
    }
    return prefectureStates;
  }

  AppData? _loadIntermediate(SharedPreferences preferences) {
    final tripsRaw = preferences.getString(intermediateTripsKey);
    final statesRaw = preferences.getString(intermediatePrefectureStatesKey);
    if (tripsRaw == null && statesRaw == null) return null;

    final trips = <Trip>[];
    final recoveredPhotos = <Photo>[];
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
        // タイトルが無効でも、読める写真は旅行未設定へ救済する。
        final normalizedTitle = title is String
            ? normalizeTripTitle(title)
            : null;
        final photos = _readLegacyFiles(record['photos'], claimedPaths);
        if (normalizedTitle == null) {
          recoveredPhotos.addAll(photos);
          continue;
        }
        trips.add(
          Trip(
            id: createEntityId('trip'),
            title: normalizedTitle,
            photos: photos,
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
      prefectureStates.addAll(_readPrefectureStates(decoded));
    }

    return AppData(
      trips: trips,
      unassignedPhotos: recoveredPhotos,
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }

  AppData _loadLegacy(SharedPreferences preferences) {
    final trips = <Trip>[];
    final unassignedPhotos = <Photo>[];
    final claimedPaths = <String>{};
    for (final record
        in preferences.getStringList(legacyTripsKey) ?? const <String>[]) {
      final separator = record.indexOf('|');
      // 「|」が無いレコードは写真部分を特定できないため救済しない。
      if (separator < 0) continue;
      final title = record.substring(0, separator);
      final normalizedTitle = normalizeTripTitle(title);
      final photos = record
          .substring(separator + 1)
          .split(';;')
          .where((path) => path.isNotEmpty)
          .where((path) => claimedPaths.add(path.replaceAll('\\', '/')))
          .map((path) => Photo(id: legacyPhotoId(path), file: File(path)))
          .where((photo) => photo.file.existsSync())
          .toList(growable: false);
      // タイトルが無効（欠損・非文字列・空白のみ）でも写真は救済する。
      if (normalizedTitle == null) {
        unassignedPhotos.addAll(photos);
        continue;
      }
      trips.add(
        Trip(
          id: createEntityId('trip'),
          title: normalizedTitle,
          photos: photos,
        ),
      );
    }

    final prefectureStates = <String, String>{};
    for (final value
        in preferences.getStringList(legacyPrefectureStatesKey) ??
            const <String>[]) {
      final separator = value.indexOf('|');
      if (separator > 0) {
        prefectureStates[value.substring(0, separator)] = value.substring(
          separator + 1,
        );
      }
    }

    return AppData(
      trips: trips,
      unassignedPhotos: unassignedPhotos,
      prefectureStates: normalizePrefectureStates(prefectureStates),
    );
  }
}
