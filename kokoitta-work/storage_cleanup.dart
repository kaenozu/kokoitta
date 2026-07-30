import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

class StorageCleanup {
  const StorageCleanup();

  static const int _maxManualBackups = 5;
  static const int _maxSafetySnapshots = 3;
  static const int _stagingMaxAgeHours = 24;

static Future<void> run({
    AppData? appData,
    Directory? documentsDirectory,
    Future<void> Function(String path)? deleteFileFn,
    Future<void> Function(String path, {bool recursive})? deleteDirFn,
  }) async {
    try {
      final directory = documentsDirectory ?? await getApplicationDocumentsDirectory();
      await _cleanupManualBackups(directory, deleteFileFn: deleteFileFn);
      await _cleanupSafetySnapshots(directory, deleteFileFn: deleteFileFn);
      await _cleanupStagingDirectories(directory, deleteDirFn: deleteDirFn);
      if (appData != null) {
        await _cleanupRestorePhotoSets(directory, appData, deleteDirFn: deleteDirFn);
        await _cleanupOrphanPhotos(directory, appData, deleteFileFn: deleteFileFn, deleteDirFn: deleteDirFn);
        await _cleanupOrphanPhotosInPhotosDir(directory, appData, deleteFileFn: deleteFileFn);
      }
    } catch (_) {
      // Cleanup failures must not block application startup.
    }
  }

  static String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  static const _backupFileNamePattern = RegExp(r'^kokoitta-backup-\d+\.zip$');

  static Future<void> _cleanupManualBackups(
    Directory directory, {
    Future<void> Function(String path)? deleteFileFn,
  }) async {
    final backupsDir = Directory('${directory.path}/backups');
    if (!await backupsDir.exists()) return;

    final files = backupsDir
        .listSync()
        .whereType<File>()
        .where((f) => _backupFileNamePattern.hasMatch(f.path))
        .toList();
    files.sort((a, b) => _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)));

    final toDelete = files.skip(_maxManualBackups);
    for (final file in toDelete) {
      try {
        if (deleteFileFn != null) {
          await deleteFileFn(file.path);
        } else {
          await file.delete();
        }
      } catch (_) {
        // Individual deletion failure must not prevent cleaning other files.
      }
    }
  }

  static Future<void> _cleanupSafetySnapshots(
    Directory directory, {
    Future<void> Function(String path)? deleteFileFn,
  }) async {
    final snapshotsDir = Directory('${directory.path}/safety-backups');
    if (!await snapshotsDir.exists()) return;

    final files = snapshotsDir
        .listSync()
        .whereType<File>()
        .where((f) => _backupFileNamePattern.hasMatch(f.path))
        .toList();
    files.sort((a, b) => _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)));

    final toDelete = files.skip(_maxSafetySnapshots);
    for (final file in toDelete) {
      try {
        if (deleteFileFn != null) {
          await deleteFileFn(file.path);
        } else {
          await file.delete();
        }
      } catch (_) {
        // Individual deletion failure must not prevent cleaning other files.
      }
    }
  }

  static int _extractTimestamp(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final match = RegExp(r'(\d+)(?:\.\w+)?$').firstMatch(fileName);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 0;
    }
    return 0;
  }

  static Future<void> _cleanupStagingDirectories(
    Directory directory, {
    Future<void> Function(String path, {bool recursive})? deleteDirFn,
  }) async {
    final now = DateTime.now();
    final maxAge = Duration(hours: _stagingMaxAgeHours);

    for (final stagingName in ['backup-staging', 'restore-staging']) {
      final stagingDir = Directory('${directory.path}/$stagingName');
      if (!await stagingDir.exists()) continue;

      final entries = stagingDir.listSync().whereType<Directory>().toList();
      for (final subDir in entries) {
        final dirName = subDir.path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
        final timestampMillis = int.tryParse(dirName);
        if (timestampMillis == null) continue;

        final dirTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
        if (now.difference(dirTime) > maxAge) {
          try {
            if (deleteDirFn != null) {
              await deleteDirFn(subDir.path, recursive: true);
            } else {
              await subDir.delete(recursive: true);
            }
          } catch (_) {
            // Individual deletion failure must not prevent cleaning other directories.
          }
        }
      }
    }
  }

  static Future<void> _cleanupRestorePhotoSets(
    Directory directory,
    AppData appData, {
    Future<void> Function(String path, {bool recursive})? deleteDirFn,
  }) async {
    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (!await photoSetsDir.exists()) return;

    final referencedPrefixes = <String>{};
    for (final file in appData.allPhotos) {
      final normalized = _normalizePath(file.path);
      final photoSetsIndex = normalized.indexOf('/photo-sets/');
      if (photoSetsIndex < 0) continue;
      final afterPhotoSets = normalized.substring(photoSetsIndex + '/photo-sets/'.length);
      final parts = afterPhotoSets.split('/');
      if (parts.isEmpty) continue;
      if (!parts.first.startsWith('restore-')) continue;
      final prefix = normalized.substring(
        0,
        photoSetsIndex + '/photo-sets/'.length + parts.first.length,
      );
      referencedPrefixes.add(prefix);
    }

    final entries = photoSetsDir.listSync().whereType<Directory>().toList();
    for (final subDir in entries) {
      final dirName = subDir.path.split(RegExp(r'[/\\]')).last;
      if (!dirName.startsWith('restore-')) continue;
      final normalizedPath = _normalizePath(subDir.path);
      final isReferenced = referencedPrefixes.any(
        (prefix) => normalizedPath == prefix || normalizedPath.startsWith('$prefix/'),
      );
      if (!isReferenced) {
        try {
          if (deleteDirFn != null) {
            await deleteDirFn(subDir.path, recursive: true);
          } else {
            await subDir.delete(recursive: true);
          }
        } catch (_) {
          // Individual deletion failure must not prevent cleaning other directories.
        }
      }
    }
  }

  static Future<void> _cleanupOrphanPhotos(
    Directory directory,
    AppData appData, {
    Future<void> Function(String path)? deleteFileFn,
    Future<void> Function(String path, {bool recursive})? deleteDirFn,
  }) async {
    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (!await photoSetsDir.exists()) return;

    final referencedPaths = <String>{};
    for (final file in appData.allPhotos) {
      referencedPaths.add(_normalizePath(file.path));
    }

    final entries = photoSetsDir.listSync().whereType<Directory>().toList();
    for (final subDir in entries) {
      final dirName = subDir.path.split(RegExp(r'[/\\]')).last;
      if (!dirName.startsWith('restore-')) continue;
      try {
        await _deleteOrphanPhotosInDirectory(subDir, referencedPaths, deleteFileFn: deleteFileFn, deleteDirFn: deleteDirFn);
      } catch (_) {
        // Individual deletion failure must not prevent cleaning other directories.
      }
    }
  }

  static Future<void> _cleanupOrphanPhotosInPhotosDir(
    Directory directory,
    AppData appData, {
    Future<void> Function(String path)? deleteFileFn,
  }) async {
    final photosDir = Directory('${directory.path}/photos');
    if (!await photosDir.exists()) return;

    final referencedPaths = <String>{};
    for (final file in appData.allPhotos) {
      referencedPaths.add(_normalizePath(file.path));
    }

    try {
      await _deleteOrphanPhotosInDirectory(photosDir, referencedPaths, deleteFileFn: deleteFileFn);
    } catch (_) {
      // Individual deletion failure must not prevent cleaning other files.
    }
  }

  static Future<void> _deleteOrphanPhotosInDirectory(
    Directory directory,
    Set<String> referencedPaths, {
    Future<void> Function(String path)? deleteFileFn,
    Future<void> Function(String path, {bool recursive})? deleteDirFn,
  }) async {
    final entries = directory.listSync();
    for (final entry in entries) {
      if (entry is Directory) {
        await _deleteOrphanPhotosInDirectory(entry, referencedPaths, deleteFileFn: deleteFileFn, deleteDirFn: deleteDirFn);
      } else if (entry is File) {
        final normalizedPath = _normalizePath(entry.path);
        if (!referencedPaths.contains(normalizedPath)) {
          try {
            if (deleteFileFn != null) {
              await deleteFileFn(entry.path);
            } else {
              await entry.delete();
            }
          } catch (_) {
            // Individual deletion failure must not prevent cleaning other files.
          }
        }
      }
    }
  }
}