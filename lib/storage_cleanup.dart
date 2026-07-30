import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

class StorageCleanup {
  const StorageCleanup();

  static const int _maxManualBackups = 5;
  static const int _maxSafetySnapshots = 3;
  static const int _stagingMaxAgeHours = 24;

  static Future<void> run({AppData? appData, Directory? documentsDirectory}) async {
    try {
      final directory = documentsDirectory ?? await getApplicationDocumentsDirectory();
      await _cleanupManualBackups(directory);
      await _cleanupSafetySnapshots(directory);
      await _cleanupStagingDirectories(directory);
      if (appData != null) {
        await _cleanupRestorePhotoSets(directory, appData);
        await _cleanupOrphanPhotos(directory, appData);
      }
    } catch (_) {
      // Cleanup failures must not block application startup.
    }
  }

  static String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  static Future<void> _cleanupManualBackups(Directory directory) async {
    final backupsDir = Directory('${directory.path}/backups');
    if (!await backupsDir.exists()) return;

    final files = backupsDir.listSync().whereType<File>().toList();
    files.sort((a, b) => _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)));

    final toDelete = files.skip(_maxManualBackups);
    for (final file in toDelete) {
      try {
        await file.delete();
      } catch (_) {
        // Individual deletion failure must not prevent cleaning other files.
      }
    }
  }

  static Future<void> _cleanupSafetySnapshots(Directory directory) async {
    final snapshotsDir = Directory('${directory.path}/safety-backups');
    if (!await snapshotsDir.exists()) return;

    final files = snapshotsDir.listSync().whereType<File>().toList();
    files.sort((a, b) => _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)));

    final toDelete = files.skip(_maxSafetySnapshots);
    for (final file in toDelete) {
      try {
        await file.delete();
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

  static Future<void> _cleanupStagingDirectories(Directory directory) async {
    final now = DateTime.now();
    final maxAge = Duration(hours: _stagingMaxAgeHours);

    for (final stagingName in ['backup-staging', 'restore-staging']) {
      final stagingDir = Directory('${directory.path}/$stagingName');
      if (!await stagingDir.exists()) continue;

      final entries = stagingDir.listSync().whereType<Directory>().toList();
      for (final subDir in entries) {
        final dirName = subDir.uri.pathSegments.last;
        final timestampMillis = int.tryParse(dirName);
        if (timestampMillis == null) continue;

        final dirTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
        if (now.difference(dirTime) > maxAge) {
          try {
            await subDir.delete(recursive: true);
          } catch (_) {
            // Individual deletion failure must not prevent cleaning other directories.
          }
        }
      }
    }
  }

  static Future<void> _cleanupRestorePhotoSets(
    Directory directory,
    AppData appData,
  ) async {
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
      final normalizedPath = _normalizePath(subDir.path);
      final isReferenced = referencedPrefixes.any(
        (prefix) => normalizedPath == prefix || normalizedPath.startsWith('$prefix/'),
      );
      if (!isReferenced) {
        try {
          await subDir.delete(recursive: true);
        } catch (_) {
          // Individual deletion failure must not prevent cleaning other directories.
        }
      }
    }
  }

  static Future<void> _cleanupOrphanPhotos(
    Directory directory,
    AppData appData,
  ) async {
    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (!await photoSetsDir.exists()) return;

    final referencedPaths = <String>{};
    for (final file in appData.allPhotos) {
      referencedPaths.add(_normalizePath(file.path));
    }

    final entries = photoSetsDir.listSync().whereType<Directory>().toList();
    for (final subDir in entries) {
      try {
        await _deleteOrphanPhotosInDirectory(subDir, referencedPaths);
      } catch (_) {
        // Individual deletion failure must not prevent cleaning other directories.
      }
    }
  }

  static Future<void> _deleteOrphanPhotosInDirectory(
    Directory directory,
    Set<String> referencedPaths,
  ) async {
    final entries = directory.listSync();
    for (final entry in entries) {
      if (entry is Directory) {
        await _deleteOrphanPhotosInDirectory(entry, referencedPaths);
      } else if (entry is File) {
        final normalizedPath = _normalizePath(entry.path);
        if (!referencedPaths.contains(normalizedPath)) {
          try {
            await entry.delete();
          } catch (_) {
            // Individual deletion failure must not prevent cleaning other files.
          }
        }
      }
    }
  }
}