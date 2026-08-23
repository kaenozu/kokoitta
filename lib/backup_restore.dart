part of 'backup_service.dart';

extension _BackupRestoreOperations on BackupService {
  Future<PreparedRestore?> prepareRestore() async {
    final file = await _backupFilePicker();
    if (file == null) return null;
    return prepareRestoreFile(file);
  }

  Future<PreparedRestore> prepareRestoreFile(File file) async {
    final length = await file.length();
    if (length > BackupService.maxCompressedBytes) {
      throw const FormatException('バックアップファイルが大きすぎます');
    }
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      return await _prepareArchive(archive);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw FormatException('ZIPを読み取れません: $error');
    } finally {
      await input.close();
    }
  }

  Future<PreparedRestore> prepareRestoreBytes(List<int> bytes) async {
    if (bytes.length > BackupService.maxCompressedBytes) {
      throw const FormatException('バックアップファイルが大きすぎます');
    }
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      return await _prepareArchive(archive);
    } catch (error) {
      if (error is FormatException) rethrow;
      throw FormatException('ZIPを読み取れません: $error');
    }
  }

  Future<PreparedRestore> _prepareArchive(Archive archive) async {
    if (archive.files.length > BackupService.maxPhotos + 20) {
      throw const FormatException('ZIP内のファイル数が上限を超えています');
    }
    final entryNames = <String>{};
    for (final entry in archive.files) {
      if (!entry.isFile) {
        throw FormatException('無効なバックアップです（ZIP内に不正なエントリがあります: ${entry.name}）');
      }
      final name = entry.name;
      if (!_isValidEntryName(name)) {
        throw FormatException('無効なバックアップです（ZIP内に不正なパスがあります: $name）');
      }
      if (name != 'manifest.json' &&
          name != 'trips.json' &&
          !name.startsWith('photos/')) {
        throw FormatException('無効なバックアップです（不明なZIPエントリがあります: $name）');
      }
      if (!entryNames.add(name)) {
        throw FormatException('無効なバックアップです（ZIP内に重複したパスがあります: $name）');
      }
    }

    final manifestFile = archive.findFile('manifest.json');
    final tripsFile = archive.findFile('trips.json');
    if (manifestFile == null || tripsFile == null) {
      throw const FormatException('manifest.json または trips.json がありません');
    }

    _validateMetadataEntrySize(
      manifestFile,
      name: 'manifest.json',
      maxBytes: BackupService.maxManifestBytes,
    );
    _validateMetadataEntrySize(
      tripsFile,
      name: 'trips.json',
      maxBytes: BackupService.maxTripsBytes,
    );

    final manifest = _decodeMap(manifestFile, 'manifest.json');
    _validateJsonValue(manifest, 'manifest.json');
    if (manifest['appId'] != BackupService.appId) {
      throw const FormatException('別のアプリのバックアップです');
    }
    final formatVersion = manifest['backupFormatVersion'];
    if (formatVersion is! int ||
        formatVersion < 1 ||
        formatVersion > BackupService.currentFormatVersion) {
      throw const FormatException('対応していないバックアップ形式です');
    }

    final rawTrips = _decodeJson(tripsFile, 'trips.json');
    _validateJsonValue(rawTrips, 'trips.json');
    final parsed = switch (formatVersion) {
      1 => _parseVersion1(rawTrips),
      2 => _parseVersion2(rawTrips),
      _ => _parseVersion3(rawTrips),
    };

    final structuralIssue = checkBackupInvariants(
      BackupInvariantCheck(
        tripCount: parsed.trips.length,
        photoCount: parsed.photoCount,
        tripIds: parsed.trips.map((trip) => trip.id),
        photos: <BackupInvariantPhoto>[
          for (final trip in parsed.trips)
            for (final photo in trip.photos)
              BackupInvariantPhoto(
                id: photo.id,
                path: photo.archivePath,
                metadataStrings: _photoMetadataStrings(photo),
              ),
          for (final photo in parsed.unassignedPhotos)
            BackupInvariantPhoto(
              id: photo.id,
              path: photo.archivePath,
              metadataStrings: _photoMetadataStrings(photo),
            ),
        ],
      ),
    );
    if (structuralIssue != null) {
      throw FormatException(structuralIssue.subject);
    }

    final declaredTripCount = manifest['tripCount'];
    final declaredPhotoCount = manifest['photoCount'];
    if (declaredTripCount is! int ||
        declaredPhotoCount is! int ||
        declaredTripCount != parsed.trips.length ||
        declaredPhotoCount != parsed.photoCount) {
      throw const FormatException('バックアップ件数が一致しません');
    }

    final checksums = <String, String>{};
    if (formatVersion >= 2) {
      if (manifest['checksumsAlgorithm'] != 'sha-256' ||
          manifest['checksums'] is! Map) {
        throw const FormatException('チェックサム情報がありません');
      }
      for (final entry in (manifest['checksums'] as Map).entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('チェックサム情報が壊れています');
        }
        checksums[entry.key as String] = entry.value as String;
      }
    }

    final documentsDirectory = await _documentsDirectoryProvider();
    final stagingDirectory = Directory(
      '${documentsDirectory.path}/restore-staging/${DateTime.now().microsecondsSinceEpoch}',
    );
    await stagingDirectory.create(recursive: true);

    var extractedBytes = 0;
    var extractedPhotos = 0;

    Future<List<PreparedPhoto>> extractPhotos(
      List<_ParsedPhoto> photos,
      String group,
    ) async {
      final prepared = <PreparedPhoto>[];
      for (var index = 0; index < photos.length; index++) {
        final photo = photos[index];
        final archivePath = photo.archivePath;
        _validateArchivePhotoPath(archivePath);
        final entry = archive.findFile(archivePath);
        if (entry == null) {
          throw FormatException('バックアップに写真が見つかりません');
        }
        if (entry.size > maxSinglePhotoBytes) {
          throw const FormatException('写真1枚の容量が上限を超えています');
        }
        final content = entry.readBytes();
        if (content == null) {
          throw const FormatException('写真を展開できません');
        }
        extractedBytes += content.length;
        extractedPhotos += 1;
        if (extractedBytes > maxUncompressedBytes ||
            extractedPhotos > BackupService.maxPhotos) {
          throw const FormatException('展開後の容量または写真枚数が上限を超えています');
        }
        if (formatVersion >= 2) {
          final expected = checksums[archivePath];
          final actual = sha256.convert(content).toString();
          if (expected == null || expected != actual) {
            throw const FormatException('写真の整合性を確認できません');
          }
        }

        final relativePath =
            '$group/${index.toString().padLeft(3, '0')}${safeFileExtension(archivePath)}';
        final destination = File('${stagingDirectory.path}/$relativePath');
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(content, flush: true);
        prepared.add(
          PreparedPhoto(
            id: photo.id,
            relativePath: relativePath,
            capturedAt: photo.capturedAt,
            location: photo.location,
            originalName: photo.originalName,
            mimeType: photo.mimeType,
          ),
        );
      }
      return prepared;
    }

    try {
      final preparedTrips = <PreparedTrip>[];
      for (var index = 0; index < parsed.trips.length; index++) {
        final trip = parsed.trips[index];
        preparedTrips.add(
          PreparedTrip(
            id: trip.id,
            title: trip.title,
            photos: await extractPhotos(trip.photos, 'trips/$index'),
          ),
        );
      }
      final unassigned = await extractPhotos(
        parsed.unassignedPhotos,
        'unassigned',
      );

      final declaredBytes = manifest['totalUncompressedBytes'];
      if (declaredBytes is! int || declaredBytes != extractedBytes) {
        throw const FormatException('バックアップ容量が一致しません');
      }

      return PreparedRestore(
        stagingDirectory: stagingDirectory,
        permanentRoot: Directory('${documentsDirectory.path}/photo-sets'),
        trips: preparedTrips,
        unassignedPhotos: unassigned,
        prefectureStates: parsed.prefectureStates,
      );
    } catch (_) {
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> shareBackup(File file) async {
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(file.path)], text: 'ここいったのバックアップ'),
    );
  }
}

Future<File?> _pickBackupFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>['zip'],
    withData: false,
  );
  if (result == null) return null;
  return File(result.xFiles.single.path);
}

Map<String, dynamic> _decodeMap(ArchiveFile file, String name) {
  final decoded = _decodeJson(file, name);
  if (decoded is! Map) throw FormatException('$name の形式が正しくありません');
  return Map<String, dynamic>.from(decoded);
}

Object? _decodeJson(ArchiveFile file, String name) {
  try {
    final bytes = file.readBytes();
    if (bytes == null) throw FormatException('$name を展開できません');
    return jsonDecode(utf8.decode(bytes));
  } catch (error) {
    throw FormatException('$name を読み取れません: $error');
  }
}

void _validateJsonValue(Object? value, String path, {int depth = 0}) {
  if (depth > 16) {
    throw FormatException('無効なバックアップです（データ構造が複雑すぎます）');
  }
  if (value is String) {
    if (value.length > backupMaxMetadataStringLength) {
      throw FormatException('無効なバックアップです（異常に長い文字列があります）');
    }
  } else if (value is List) {
    if (value.length > 500) {
      throw FormatException('無効なバックアップです（データ量が多すぎます）');
    }
    for (var i = 0; i < value.length; i++) {
      _validateJsonValue(value[i], '$path[$i]', depth: depth + 1);
    }
  } else if (value is Map) {
    if (value.length > 400) {
      throw FormatException('無効なバックアップです（データ量が多すぎます）');
    }
    for (final entry in value.entries) {
      _validateJsonValue(entry.value, '$path/${entry.key}', depth: depth + 1);
    }
  }
}

bool _isValidEntryName(String name) {
  if (name.isEmpty) return false;
  if (name.startsWith('/')) return false;
  if (name.contains('\\')) return false;
  return !name.split('/').any((s) => s.isEmpty || s == '.' || s == '..');
}

void _validateMetadataEntrySize(
  ArchiveFile file, {
  required String name,
  required int maxBytes,
}) {
  final size = file.size;
  if (size <= 0) {
    throw FormatException('無効なバックアップです（$nameの容量が正しくありません）');
  }
  if (size > maxBytes) {
    throw FormatException('無効なバックアップです（$nameの容量が上限を超えています）');
  }
}

_ParsedBackup _parseVersion1(Object? value) {
  if (value is! List) {
    throw const FormatException('旅行データの形式が正しくありません');
  }
  final trips = <_ParsedTrip>[];
  for (final recordValue in value) {
    if (recordValue is! Map) {
      throw const FormatException('旅行データが壊れています');
    }
    final record = Map<String, dynamic>.from(recordValue);
    final titleValue = record['title'];
    if (titleValue is! String) {
      continue;
    }
    final title = normalizeTripTitle(titleValue);
    if (title == null) {
      continue;
    }
    trips.add(
      _ParsedTrip(
        id: createEntityId('trip'),
        title: title,
        photos: _parseLegacyPhotoPaths(
          _requiredStringList(record['photos'], '写真一覧'),
        ),
      ),
    );
  }
  return _ParsedBackup(
    trips: trips,
    unassignedPhotos: const <_ParsedPhoto>[],
    prefectureStates: const <String, String>{},
  );
}

_ParsedBackup _parseVersion2(Object? value) {
  if (value is! Map) {
    throw const FormatException('旅行データの形式が正しくありません');
  }
  final root = Map<String, dynamic>.from(value);
  final tripsValue = root['trips'];
  if (tripsValue is! List) {
    throw const FormatException('旅行データがありません');
  }

  final trips = <_ParsedTrip>[];
  final seenIds = <String>{};
  for (final recordValue in tripsValue) {
    if (recordValue is! Map) {
      throw const FormatException('旅行データが壊れています');
    }
    final record = Map<String, dynamic>.from(recordValue);
    var id = _requiredString(record['id'], '旅行ID');
    if (!seenIds.add(id)) id = createEntityId('trip');
    final titleValue = record['title'];
    if (titleValue is! String) {
      continue;
    }
    final title = normalizeTripTitle(titleValue);
    if (title == null) {
      continue;
    }
    trips.add(
      _ParsedTrip(
        id: id,
        title: title,
        photos: _parseLegacyPhotoPaths(
          _requiredStringList(record['photos'], '写真一覧'),
        ),
      ),
    );
  }

  final prefectureStates = <String, String>{};
  final statesValue = root['prefectureStates'];
  if (statesValue is Map) {
    for (final entry in statesValue.entries) {
      if (entry.key is String && entry.value is String) {
        prefectureStates[entry.key as String] = entry.value as String;
      }
    }
  }

  return _ParsedBackup(
    trips: trips,
    unassignedPhotos: _parseLegacyPhotoPaths(
      _requiredStringList(root['unassignedPhotos'], '旅行未設定の写真一覧'),
    ),
    prefectureStates: normalizePrefectureStates(prefectureStates),
  );
}

_ParsedBackup _parseVersion3(Object? value) {
  if (value is! Map) {
    throw const FormatException('旅行データの形式が正しくありません');
  }
  final root = Map<String, dynamic>.from(value);
  final tripsValue = root['trips'];
  if (tripsValue is! List) {
    throw const FormatException('旅行データがありません');
  }

  final trips = <_ParsedTrip>[];
  for (final recordValue in tripsValue) {
    if (recordValue is! Map) {
      throw const FormatException('旅行データが壊れています');
    }
    final record = Map<String, dynamic>.from(recordValue);
    final id = _requiredString(record['id'], '旅行ID');
    final titleValue = record['title'];
    if (titleValue is! String) {
      continue;
    }
    final title = normalizeTripTitle(titleValue);
    if (title == null) {
      continue;
    }
    trips.add(
      _ParsedTrip(
        id: id,
        title: title,
        photos: _requiredPhotoList(record['photos'], '写真一覧'),
      ),
    );
  }

  final prefectureStates = <String, String>{};
  final statesValue = root['prefectureStates'];
  if (statesValue is Map) {
    for (final entry in statesValue.entries) {
      if (entry.key is String && entry.value is String) {
        prefectureStates[entry.key as String] = entry.value as String;
      }
    }
  }

  return _ParsedBackup(
    trips: trips,
    unassignedPhotos: _requiredPhotoList(
      root['unassignedPhotos'],
      '旅行未設定の写真一覧',
    ),
    prefectureStates: normalizePrefectureStates(prefectureStates),
  );
}

/// v1/v2（写真IDを持たない形式）の写真パス一覧を、
/// 新規ID付きのパース済み写真へ変換する。
List<_ParsedPhoto> _parseLegacyPhotoPaths(List<String> paths) {
  return paths
      .map((path) => _ParsedPhoto(id: createPhotoId(), archivePath: path))
      .toList();
}

List<_ParsedPhoto> _requiredPhotoList(Object? value, String label) {
  if (value is! List) throw FormatException('$label が壊れています');
  final result = <_ParsedPhoto>[];
  for (final item in value) {
    if (item is! Map) throw FormatException('$label が壊れています');
    final record = Map<String, dynamic>.from(item);
    result.add(
      _ParsedPhoto(
        id: _requiredString(record['id'], '写真ID'),
        archivePath: _requiredString(record['archivePath'], '写真パス'),
        capturedAt: _readOptionalDateTime(record['capturedAt']),
        location: _readOptionalString(record['location']),
        originalName: _readOptionalString(record['originalName']),
        mimeType: _readOptionalString(record['mimeType']),
      ),
    );
  }
  return result;
}

DateTime? _readOptionalDateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

String? _readOptionalString(Object? value) => value is String ? value : null;

String _requiredString(Object? value, String label) {
  if (value is! String ||
      value.isEmpty ||
      value.length > backupMaxEntityIdLength) {
    throw FormatException('$label が壊れています');
  }
  return value;
}

/// 共通検査へ渡す写真metadata文字列一覧。作成側が書き込む内容と同じ形にする。
List<String> _photoMetadataStrings(_ParsedPhoto photo) => <String>[
  if (photo.capturedAt != null) photo.capturedAt!.toIso8601String(),
  if (photo.location != null) photo.location!,
  if (photo.originalName != null) photo.originalName!,
  if (photo.mimeType != null) photo.mimeType!,
];

List<String> _requiredStringList(Object? value, String label) {
  if (value is! List) throw FormatException('$label が壊れています');
  final result = <String>[];
  for (final item in value) {
    if (item is! String) throw FormatException('$label が壊れています');
    result.add(item);
  }
  return result;
}

void _validateArchivePhotoPath(String path) {
  final segments = path.split('/');
  if (!path.startsWith('photos/') ||
      path.startsWith('/') ||
      segments.contains('..') ||
      path.contains('\\')) {
    // アーカイブ内パスは外部入力のため、UIへ露出するメッセージに含めない。
    throw const FormatException('バックアップ内の写真パスが不正です');
  }
}
