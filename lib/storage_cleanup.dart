import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

typedef DeleteFileFn = Future<void> Function(String path);
typedef DeleteDirFn = Future<void> Function(
  String path, {
  required bool recursive,
});

class StorageCleanup {
  const StorageCleanup();

  static const int _maxManualBackups = 5;
  static const int _maxSafetySnapshots = 3;
  static const int _stagingMaxAgeHours = 24;
  static const String _restoreDirPrefix = 'restore-';

  static final RegExp _backupFileNamePattern = RegExp(
    r'^kokoitta-backup-\d+\.zip$',
  );

  static Future<void> run({
    AppData? appData,
    Directory? documentsDirectory,
    DeleteFileFn? deleteFileFn,
    DeleteDirFn? deleteDirFn,
  }) async {
    final deleteFile = deleteFileFn ??
        (String path) async {
          await File(path).delete();
        };
    final deleteDirectory = deleteDirFn ??
        (String path, {required bool recursive}) async {
          await Directory(path).delete(recursive: recursive);
        };

    try {
      final directory =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      await _cleanupManualBackups(directory, deleteFile);
      await _cleanupSafetySnapshots(directory, deleteFile);
      await _cleanupStagingDirectories(directory, deleteDirectory);
      if (appData != null) {
        await _cleanupRestorePhotoSets(directory, appData, deleteDirectory);
        await _cleanupOrphanPhotos(directory, appData, deleteFile);
      }
    } catch (error) {
      debugPrint('Storage cleanup failed: $error');
    }
  }

  static String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  static String _basename(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }

  static Future<void> _cleanupManualBackups(
    Directory directory,
    DeleteFileFn deleteFile,
  ) async {
    final backupsDir = Directory('${directory.path}/backups');
    if (!await backupsDir.exists()) return;

    final files = _listFiles(backupsDir)
        .where((file) => _backupFileNamePattern.hasMatch(_basename(file.path)))
        .toList()
      ..sort(
        (a, b) =>
            _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)),
      );

    for (final file in files.skip(_maxManualBackups)) {
      await _tryDeleteFile(file, deleteFile, label: 'backup');
    }
  }

  static Future<void> _cleanupSafetySnapshots(
    Directory directory,
    DeleteFileFn deleteFile,
  ) async {
    final snapshotsDir = Directory('${directory.path}/safety-backups');
    if (!await snapshotsDir.exists()) return;

    final files = _listFiles(snapshotsDir)
        .where((file) => _backupFileNamePattern.hasMatch(_basename(file.path)))
        .toList()
      ..sort(
        (a, b) =>
            _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)),
      );

    for (final file in files.skip(_maxSafetySnapshots)) {
      await _tryDeleteFile(file, deleteFile, label: 'safety snapshot');
    }
  }

  static int _extractTimestamp(String path) {
    final match = RegExp(r'(\d+)(?:\.\w+)?$').firstMatch(_basename(path));
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static Future<void> _cleanupStagingDirectories(
    Directory directory,
    DeleteDirFn deleteDirectory,
  ) async {
    final now = DateTime.now();
    const maxAge = Duration(hours: _stagingMaxAgeHours);

    for (final stagingName in const ['backup-staging', 'restore-staging']) {
      final stagingDir = Directory('${directory.path}/$stagingName');
      if (!await stagingDir.exists()) continue;

      for (final subDir in _listDirectories(stagingDir)) {
        final dirName = _basename(subDir.path);
        final timestampMillis = int.tryParse(dirName);
        if (timestampMillis == null) continue;

        final createdAt = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
        if (now.difference(createdAt) <= maxAge) continue;

        await _tryDeleteDirectory(
          subDir,
          deleteDirectory,
          label: 'staging directory',
        );
      }
    }
  }

  static Future<void> _cleanupRestorePhotoSets(
    Directory directory,
    AppData appData,
    DeleteDirFn deleteDirectory,
  ) async {
    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (!await photoSetsDir.exists()) return;

    final referencedRestoreDirectories = <String>{};
    for (final file in appData.allPhotos) {
      final normalized = _normalizePath(file.path);
      final markerIndex = normalized.indexOf('/photo-sets/');
      if (markerIndex < 0) continue;

      final relative = normalized.substring(markerIndex + '/photo-sets/'.length);
      final firstSegment = relative.split('/').first;
      if (!firstSegment.startsWith(_restoreDirPrefix)) continue;

      referencedRestoreDirectories.add(
        normalized.substring(
          0,
          markerIndex + '/photo-sets/'.length + firstSegment.length,
        ),
      );
    }

    for (final subDir in _listDirectories(photoSetsDir)) {
      final dirName = _basename(subDir.path);
      if (!dirName.startsWith(_restoreDirPrefix)) continue;

      final normalized = _normalizePath(subDir.path);
      if (referencedRestoreDirectories.contains(normalized)) continue;

      await _tryDeleteDirectory(
        subDir,
        deleteDirectory,
        label: 'restore photo set',
      );
    }
  }

  static Future<void> _cleanupOrphanPhotos(
    Directory directory,
    AppData appData,
    DeleteFileFn deleteFile,
  ) async {
    final referencedPaths = <String>{
      for (final file in appData.allPhotos) _normalizePath(file.path),
    };

    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (await photoSetsDir.exists()) {
      for (final subDir in _listDirectories(photoSetsDir)) {
        if (!_basename(subDir.path).startsWith(_restoreDirPrefix)) continue;
        await _deleteOrphansRecursively(subDir, referencedPaths, deleteFile);
      }
    }

    final photosDir = Directory('${directory.path}/photos');
    if (await photosDir.exists()) {
      await _deleteOrphansRecursively(photosDir, referencedPaths, deleteFile);
    }
  }

  static Future<void> _deleteOrphansRecursively(
    Directory directory,
    Set<String> referencedPaths,
    DeleteFileFn deleteFile,
  ) async {
    for (final entry in _listEntities(directory)) {
      if (entry is Directory) {
        await _deleteOrphansRecursively(entry, referencedPaths, deleteFile);
      } else if (entry is File &&
          !referencedPaths.contains(_normalizePath(entry.path))) {
        await _tryDeleteFile(entry, deleteFile, label: 'orphan photo');
      }
    }
  }

  static Future<void> _tryDeleteFile(
    File file,
    DeleteFileFn deleteFile, {
    required String label,
  }) async {
    try {
      await deleteFile(file.path);
    } catch (error) {
      debugPrint(
        'Storage cleanup: failed to delete $label ${_basename(file.path)}: $error',
      );
    }
  }

  static Future<void> _tryDeleteDirectory(
    Directory directory,
    DeleteDirFn deleteDirectory, {
    required String label,
  }) async {
    try {
      await deleteDirectory(directory.path, recursive: true);
    } catch (error) {
      debugPrint(
        'Storage cleanup: failed to delete $label ${_basename(directory.path)}: $error',
      );
    }
  }

  static List<File> _listFiles(Directory directory) {
    try {
      return directory.listSync().whereType<File>().toList();
    } catch (error) {
      debugPrint('Storage cleanup: failed to list files in $directory: $error');
      return <File>[];
    }
  }

  static List<Directory> _listDirectories(Directory directory) {
    try {
      return directory.listSync().whereType<Directory>().toList();
    } catch (error) {
      debugPrint(
        'Storage cleanup: failed to list directories in $directory: $error',
      );
      return <Directory>[];
    }
  }

  static List<FileSystemEntity> _listEntities(Directory directory) {
    try {
      return directory.listSync();
    } catch (error) {
      debugPrint(
        'Storage cleanup: failed to list entities in $directory: $error',
      );
      return <FileSystemEntity>[];
    }
  }
}
