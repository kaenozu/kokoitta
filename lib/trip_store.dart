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

  /// 最後の [load] で検出した、保存データが参照するがファイルが存在しない写真。
  ///
  /// 読み込み時は従来どおり欠損写真を読み飛ばす（実在写真を奪わない）ため、
  /// 欠損情報は AppData に含まれない。UI への通知・復旧はこの別経路を使う。
  List<MissingPhoto> missingPhotos = const <MissingPhoto>[];

  Future<AppData> load() async {
    missingPhotos = const <MissingPhoto>[];
    final preferences = await _preferencesFactory();

    final pending = preferences.getString(pendingKey);
    if (pending != null) {
      try {
        final recovered = _decode(pending);
        // 欠損写真がある間は正規化保存をスキップする。_decode は欠損を読み飛ばす
        // ため、そのまま _encode すると欠損レコードが消えて再割り当て不能になる。
        if (missingPhotos.isEmpty) {
          final canonical = _canonicalize(recovered);
          final encoded = jsonEncode(_encode(canonical));
          await _writeCanonical(preferences, encoded);
        }
        return recovered;
      } on FormatException {
        await preferences.remove(pendingKey);
      }
    }

    final stored = preferences.getString(dataKey);
    if (stored != null) {
      final recovered = _decode(stored);
      // 欠損写真がある間は正規化保存をスキップする（欠損レコード保持のため）。
      if (missingPhotos.isEmpty) {
        final canonical = _canonicalize(recovered);
        final canonicalEncoded = jsonEncode(_encode(canonical));
        if (canonicalEncoded != stored) {
          final written = await preferences.setString(
            dataKey,
            canonicalEncoded,
          );
          if (!written) {
            throw FileSystemException('保存データを書き込めませんでした');
          }
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
          photos: _readLegacyFiles(
            record['photos'],
            claimedPaths,
            tripId: id,
            tripTitle: normalizedTitle,
          ),
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
          photos: _readPhotos(
            record['photos'],
            claimedPaths,
            claimedIds,
            tripId: id,
            tripTitle: normalizedTitle,
          ),
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
  /// 欠損ファイルはID・パスをclaimしないため、後続する実在写真を奪わない。
  /// 無視した欠損写真は [missingPhotos] へ記録する（[tripId]・[tripTitle] は
  /// 所属旅行の情報。旅行未設定・救済写真は空文字）。
  List<Photo> _readLegacyFiles(
    Object? value,
    Set<String> claimedPaths, {
    String tripId = '',
    String tripTitle = '',
  }) {
    if (value == null) return const <Photo>[];
    if (value is! List) {
      throw const FormatException('写真データが壊れています');
    }

    final photos = <Photo>[];
    for (final path in value) {
      if (path is! String) {
        throw const FormatException('写真パスが壊れています');
      }
      final normalizedPath = path.replaceAll('\\', '/');
      if (claimedPaths.contains(normalizedPath)) continue;
      final file = File(path);
      if (!file.existsSync()) {
        missingPhotos = <MissingPhoto>[
          ...missingPhotos,
          MissingPhoto(
            id: legacyPhotoId(path),
            path: path,
            tripId: tripId,
            tripTitle: tripTitle,
          ),
        ];
        continue;
      }
      claimedPaths.add(normalizedPath);
      photos.add(Photo(id: legacyPhotoId(path), file: file));
    }
    return photos;
  }

  /// v3形式の写真レコードを読む。パス・IDの重複は読み込み時に最初の1件へ
  /// 集約し、欠損ファイルは無視する。欠損ファイルはID・パスをclaimしないため、
  /// 後続する実在写真（同一ID・別パス）を奪わない。metadataは壊れていても
  /// nullへ正規化する。無視した欠損写真は [missingPhotos] へ記録する。
  List<Photo> _readPhotos(
    Object? value,
    Set<String> claimedPaths,
    Set<String> claimedIds, {
    String tripId = '',
    String tripTitle = '',
  }) {
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
      final file = File(path);
      if (!file.existsSync()) {
        missingPhotos = <MissingPhoto>[
          ...missingPhotos,
          MissingPhoto(
            id: id,
            path: path,
            tripId: tripId,
            tripTitle: tripTitle,
          ),
        ];
        continue;
      }
      claimedPaths.add(normalizedPath);
      claimedIds.add(id);
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

    // タイトル妥当性と写真構造評価を分離するため、全レコードを先に構造解析し、
    // 有効タイトル旅行の写真値と無効タイトル旅行の写真値へ分類する。これにより
    // レコード順に関係なく、有効タイトル旅行 → 救済写真の優先順位が成立する。
    final validRecords = <({String title, Object? photos})>[];
    final invalidPhotoValues = <Object?>[];
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
        if (normalizedTitle == null) {
          invalidPhotoValues.add(record['photos']);
          continue;
        }
        validRecords.add((title: normalizedTitle, photos: record['photos']));
      }
    }

    // 有効タイトル旅行の写真を先に読み込み、claimする。
    final trips = <Trip>[];
    final claimedPaths = <String>{};
    for (final record in validRecords) {
      final tripId = createEntityId('trip');
      trips.add(
        Trip(
          id: tripId,
          title: record.title,
          photos: _readLegacyFiles(
            record.photos,
            claimedPaths,
            tripId: tripId,
            tripTitle: record.title,
          ),
        ),
      );
    }

    // 無効タイトル旅行の写真を最後に読み込み、未claimの写真だけ救済する。
    final recoveredPhotos = _readAndRecover(
      invalidPhotoValues,
      claimedPaths,
      const <String>{},
      true,
    );

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
    // タイトル妥当性と写真部分の特定を分離するため、全レコードを先に構造解析し、
    // 有効タイトル旅行の写真部分と無効タイトル旅行の写真部分へ分類する。これに
    // よりレコード順に関係なく、有効タイトル旅行 → 救済写真の優先順位が成立する。
    final allRecords =
        preferences.getStringList(legacyTripsKey) ?? const <String>[];
    final validRecords = <({String title, String photosPart})>[];
    final invalidPhotosParts = <String>[];
    for (final record in allRecords) {
      final separator = record.indexOf('|');
      // 「|」が無いレコードは写真部分を特定できないため救済しない。
      if (separator < 0) continue;
      final title = record.substring(0, separator);
      final normalizedTitle = normalizeTripTitle(title);
      final photosPart = record.substring(separator + 1);
      if (normalizedTitle == null) {
        invalidPhotosParts.add(photosPart);
        continue;
      }
      validRecords.add((title: normalizedTitle, photosPart: photosPart));
    }

    // 有効タイトル旅行の写真を先に読み込み、claimする。
    final trips = <Trip>[];
    final claimedPaths = <String>{};
    for (final record in validRecords) {
      trips.add(
        Trip(
          id: createEntityId('trip'),
          title: record.title,
          photos: _readLegacyPhotosPart(record.photosPart, claimedPaths),
        ),
      );
    }

    // 無効タイトル旅行の写真を最後に読み込み、未claimの写真だけ救済する。
    final unassignedPhotos = <Photo>[];
    for (final photosPart in invalidPhotosParts) {
      unassignedPhotos.addAll(_readLegacyPhotosPart(photosPart, claimedPaths));
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

  /// legacy形式の写真部分（`;;`区切りのパス文字列）を読む。パスはセパレータ
  /// 表記違い（`\` と `/`）を正規化して同一扱いにし、欠損ファイルは読み飛ばす。
  /// 欠損ファイルはパスをclaimしないため、後続する実在写真を奪わない。
  List<Photo> _readLegacyPhotosPart(
    String photosPart,
    Set<String> claimedPaths,
  ) {
    final photos = <Photo>[];
    for (final path in photosPart.split(';;')) {
      if (path.isEmpty) continue;
      final normalizedPath = path.replaceAll('\\', '/');
      if (claimedPaths.contains(normalizedPath)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      claimedPaths.add(normalizedPath);
      photos.add(Photo(id: legacyPhotoId(path), file: file));
    }
    return photos;
  }

  /// 欠損写真のレコードを保存データから明示的に削除する。
  ///
  /// [targets] に含まれる写真IDを持つレコードを、所属旅行（または旅行未設定）
  /// の photos から取り除いて再保存する。IDが一致しないレコードは変更しない。
  /// 削除後は再読み込みした [AppData] を返す。
  Future<AppData> discardMissingPhotos(Iterable<MissingPhoto> targets) async {
    final targetIds = targets.map((missing) => missing.id).toSet();
    return _rewritePhotos(
      (records) =>
          records.where((record) => !targetIds.contains(record['id'])).toList(),
    );
  }

  /// 欠損写真のレコードを新しいファイルへ再割り当てする。
  ///
  /// ID・metadataは維持し、path だけを [newFile] のパスへ置き換えて再保存する。
  /// 再割り当て後は再読み込みした [AppData] を返す。新しいパスのファイルが
  /// 実在しない場合は、次の [load] で再び欠損として検出される。
  Future<AppData> reassignMissingPhoto(
    MissingPhoto target,
    File newFile,
  ) async {
    return _rewritePhotos(
      (records) => [
        for (final record in records)
          if (record['id'] == target.id)
            <String, Object?>{...record, 'path': newFile.path}
          else
            record,
      ],
    );
  }

  /// 保存データ（v3）の全写真レコードを [transform] で書き換えて再保存し、
  /// 再読み込みした [AppData] を返す。
  ///
  /// v2形式が保存されている場合（未マイグレーション）は書き換え対象の
  /// レコード構造が異なるため、何もせず再読み込みだけを行う。
  Future<AppData> _rewritePhotos(
    List<Map<String, Object?>> Function(List<Map<String, Object?>>) transform,
  ) async {
    final preferences = await _preferencesFactory();
    final raw = preferences.getString(dataKey);
    if (raw == null) {
      return load();
    }
    final Object? decoded;
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
      // v2等の旧形式はレコード構造が異なるため書き換えず、再読み込みのみ。
      return load();
    }

    List<Object?> rewriteList(Object? value) {
      if (value is! List) return const <Object?>[];
      return transform(
        value
            .whereType<Map>()
            .map((entry) => Map<String, Object?>.from(entry))
            .toList(),
      );
    }

    final tripsValue = decoded['trips'];
    if (tripsValue is! List) {
      throw const FormatException('旅行データがありません');
    }
    for (final trip in tripsValue) {
      if (trip is! Map) continue;
      trip['photos'] = rewriteList(trip['photos']);
    }
    decoded['unassignedPhotos'] = rewriteList(decoded['unassignedPhotos']);

    // _decode → _encode を経由すると欠損写真（読み飛ばし対象）のレコードまで
    // 消えるため、置き換え後の JSON をそのまま保存する。既存レコードの
    // 構造は変わらない（path/id のみ変更・削除）ため canonical 性は保たれる。
    final encoded = jsonEncode(decoded);
    final written = await preferences.setString(dataKey, encoded);
    if (!written) {
      throw FileSystemException('保存データを書き込めませんでした');
    }
    await preferences.remove(pendingKey);
    return load();
  }
}
