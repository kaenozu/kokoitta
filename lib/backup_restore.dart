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
        throw FormatException(
          '無効なバックアップです（ZIP内に不正なエントリがあります: ${entry.name}）',
        );
      }
      final name = entry.name;
      if (!_isValidEntryName(name)) {
        throw FormatException(
          '無効なバックアップです（ZIP内に不正なパスがあります: $name）',
        );
      }
      if (name != 'manifest.json' &&
          name != 'trips.json' &&
          !name.startsWith('photos/')) {
        throw FormatException(
          '無効なバックアップです（不明なZIPエントリがあります: $name）',
        );
      }
      if (!entryNames.add(name)) {
        throw FormatException(
          '無効なバックアップです（ZIP内に重複したパスがあります: $name）',
        );
      }
    }

    final manifestFile = archive.findFile('manifest.json');
    final tripsFile = archive.findFile('trips.json');
    if (manifestFile == null || tripsFile == null) {
      throw const FormatException(
        'manifest.json または trips.json がありません',
      );
    }

    if (manifestFile.size > BackupService.maxManifestBytes) {
      throw const FormatException(
        '無効なバックアップです（manifest.jsonの容量が上限を超えています）',
      );
    }
    if (tripsFile.size > BackupService.maxTripsBytes) {
      throw const FormatException(
        '無効なバックアップです（trips.jsonの容量が上限を超えています）',
      );
    }

    final manifest = _decodeMap(manifestFile, 'manifest.json');
    _validateJsonValue(manifest, 'manifest.json');
    if (manifest['appId'] != BackupService.appId) {
      throw const FormatException('別のアプリのバックアップです');
    }
    final formatVersion = manifest['backupFormatVersion'];
    if (formatVersion != 1 &&
        formatVersion != BackupService.currentFormatVersion) {
      throw const FormatException('対応していないバックアップ形式です');
    }

    final rawTrips = _decodeJson(tripsFile, 'trips.json');
    _validateJsonValue(rawTrips, 'trips.json');
    final parsed = formatVersion == 1
        ? _parseVersion1(rawTrips)
        : _parseVersion2(rawTrips);
    if (parsed.trips.length > BackupService.maxTrips ||
        parsed.photoCount > BackupService.maxPhotos) {
      throw const FormatException('無料版の旅行数または写真枚数の上限を超えています');
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
    if (formatVersion == BackupService.currentFormatVersion) {
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
    final seenArchivePaths = <String>{};

    Future<List<String>> extractPhotos(
      List<String> archivePaths,
      String group,
    ) async {
      final relativePaths = <String>[];
      for (var index = 0; index < archivePaths.length; index++) {
        final archivePath = archivePaths[index];
        _validateArchivePhotoPath(archivePath);
        if (!seenArchivePaths.add(archivePath)) {
          throw FormatException('同じ写真が複数回参照されています: $archivePath');
        }
        final entry = archive.findFile(archivePath);
        if (entry == null) {
          throw FormatException('写真が見つかりません: $archivePath');
        }
        if (entry.size > BackupService.maxSinglePhotoBytes) {
          throw FormatException('写真1枚の容量が上限を超えています: $archivePath');
        }
        final content = entry.readBytes();
        if (content == null) {
          throw FormatException('写真を展開できません: $archivePath');
        }
        extractedBytes += content.length;
        extractedPhotos += 1;
        if (extractedBytes > BackupService.maxUncompressedBytes ||
            extractedPhotos > BackupService.maxPhotos) {
          throw const FormatException('展開後の容量または写真枚数が上限を超えています');
        }
        if (formatVersion == BackupService.currentFormatVersion) {
          final expected = checksums[archivePath];
          final actual = sha256.convert(content).toString();
          if (expected == null || expected != actual) {
            throw FormatException('写真の整合性を確認できません: $archivePath');
          }
        }

        final relativePath =
            '$group/${index.toString().padLeft(3, '0')}${_safeExtension(archivePath)}';
        final destination = File('${stagingDirectory.path}/$relativePath');
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(content, flush: true);
        relativePaths.add(relativePath);
      }
      return relativePaths;
    }

    try {
      final preparedTrips = <PreparedTrip>[];
      for (var index = 0; index < parsed.trips.length; index++) {
        final trip = parsed.trips[index];
        preparedTrips.add(
          PreparedTrip(
            id: trip.id,
            title: trip.title,
            relativePhotoPaths: await extractPhotos(
              trip.photoPaths,
              'trips/$index',
            ),
          ),
        );
      }
      final unassigned = await extractPhotos(
        parsed.unassignedPhotoPaths,
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
        unassignedRelativePhotoPaths: unassigned,
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
      ShareParams(
        files: <XFile>[XFile(file.path)],
        text: 'ここいったのバックアップ',
      ),
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

Map<String, dynamic> _decodeMap(
  ArchiveFile file,
  String name,
) {
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
    if (value.length > 500) {
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
    if (value.length > 100) {
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
    trips.add(
      _ParsedTrip(
        id: createEntityId('trip'),
        title: _requiredString(record['title'], '旅行名'),
        photoPaths: _requiredStringList(record['photos'], '写真一覧'),
      ),
    );
  }
  return _ParsedBackup(
    trips: trips,
    unassignedPhotoPaths: const <String>[],
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
    trips.add(
      _ParsedTrip(
        id: id,
        title: _requiredString(record['title'], '旅行名'),
        photoPaths: _requiredStringList(record['photos'], '写真一覧'),
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
    unassignedPhotoPaths: _requiredStringList(
      root['unassignedPhotos'],
      '旅行未設定の写真一覧',
    ),
    prefectureStates: prefectureStates,
  );
}

String _requiredString(Object? value, String label) {
  if (value is! String || value.isEmpty || value.length > 200) {
    throw FormatException('$label が壊れています');
  }
  return value;
}

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
    throw FormatException('不正な写真パスです: $path');
  }
}

String _safeExtension(String path) {
  final fileName = path.split(RegExp(r'[/\\]')).last;
  final separator = fileName.lastIndexOf('.');
  if (separator < 0) return '.jpg';
  final extension = fileName.substring(separator).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)
      ? extension
      : '.jpg';
}
