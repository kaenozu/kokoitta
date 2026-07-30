import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class StorageCleanup {
  const StorageCleanup();

  static const int _maxManualBackups = 5;
  static const int _maxSafetySnapshots = 3;
  static const int _stagingMaxAgeHours = 24;

  static const String _restoreDirPrefix = 'restore-';

  static Future<void> run({
    AppData? appData,
    Directory? documentsDirectory,
    Future<void> Function(File file)? onDeleteFile,
    Future<void> Function(Directory dir)? onDeleteDirectory,
  }) async {
    try {
      final directory =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      await _cleanupManualBackups(directory, onDeleteFile: onDeleteFile);
      await _cleanupSafetySnapshots(directory, onDeleteFile: onDeleteFile);
      await _cleanupStagingDirectories(
        directory,
        onDeleteDirectory: onDeleteDirectory,
      );
      if (appData != null) {
        await _cleanupRestorePhotoSets(
          directory,
          appData,
          onDeleteDirectory: onDeleteDirectory,
        );
        await _cleanupOrphanPhotos(
          directory,
          appData,
          onDeleteFile: onDeleteFile,
        );
      }
    } catch (e) {
      debugPrint('Storage cleanup failed: $e');
    }
  }

  static String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  static Future<void> _cleanupManualBackups(
    Directory directory, {
    Future<void> Function(File file)? onDeleteFile,
  }) async {
    final backupsDir = Directory('${directory.path}/backups');
    if (!await backupsDir.exists()) return;

    final files = _listFilesSync(backupsDir);
    files.sort(
      (a, b) =>
          _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)),
    );

    final toDelete = files.skip(_maxManualBackups);
    for (final file in toDelete) {
      try {
        if (onDeleteFile != null) {
          await onDeleteFile(file);
        } else {
          await file.delete();
        }
      } catch (e) {
        debugPrint(
          'Storage cleanup: failed to delete backup ${file.path.split(RegExp(r'[/\\]')).last}: $e',
        );
      }
    }
  }

  static Future<void> _cleanupSafetySnapshots(
    Directory directory, {
    Future<void> Function(File file)? onDeleteFile,
  }) async {
    final snapshotsDir = Directory('${directory.path}/safety-backups');
    if (!await snapshotsDir.exists()) return;

    final files = _listFilesSync(snapshotsDir);
    files.sort(
      (a, b) =>
          _extractTimestamp(b.path).compareTo(_extractTimestamp(a.path)),
    );

    final toDelete = files.skip(_maxSafetySnapshots);
    for (final file in toDelete) {
      try {
        if (onDeleteFile != null) {
          await onDeleteFile(file);
        } else {
          await file.delete();
        }
      } catch (e) {
        debugPrint(
          'Storage cleanup: failed to delete snapshot ${file.path.split(RegExp(r'[/\\]')).last}: $e',
        );
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
    Future<void> Function(Directory dir)? onDeleteDirectory,
  }) async {
    final now = DateTime.now();
    final maxAge = Duration(hours: _stagingMaxAgeHours);

    for (final stagingName in ['backup-staging', 'restore-staging']) {
      final stagingDir = Directory('${directory.path}/$stagingName');
      if (!await stagingDir.exists()) continue;

      final entries = _listDirectoriesSync(stagingDir);
      for (final subDir in entries) {
        final dirName = subDir.path.split(RegExp(r'[/\\]')).last;
        final timestampMillis = int.tryParse(dirName);
        if (timestampMillis == null) continue;

        final dirTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
        if (now.difference(dirTime) > maxAge) {
          try {
            if (onDeleteDirectory != null) {
              await onDeleteDirectory(subDir);
            } else {
              await subDir.delete(recursive: true);
            }
          } catch (e) {
            debugPrint(
              'Storage cleanup: failed to delete staging dir $dirName: $e',
            );
          }
        }
      }
    }
  }

  static Future<void> _cleanupRestorePhotoSets(
    Directory directory,
    AppData appData, {
    Future<void> Function(Directory dir)? onDeleteDirectory,
  }) async {
    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (!await photoSetsDir.exists()) return;

    final referencedPrefixes = <String>{};
    for (final file in appData.allPhotos) {
      final normalized = _normalizePath(file.path);
      final photoSetsIndex = normalized.indexOf('/photo-sets/');
      if (photoSetsIndex < 0) continue;
      final afterPhotoSets =
          normalized.substring(photoSetsIndex + '/photo-sets/'.length);
      final parts = afterPhotoSets.split('/');
      if (parts.isEmpty) continue;
      if (!parts.first.startsWith(_restoreDirPrefix)) continue;
      final prefix = normalized.substring(
        0,
        photoSetsIndex + '/photo-sets/'.length + parts.first.length,
      );
      referencedPrefixes.add(prefix);
    }

    final entries = _listDirectoriesSync(photoSetsDir);
    for (final subDir in entries) {
      final subDirName = subDir.path.split(RegExp(r'[/\\]')).last;
      if (!subDirName.startsWith(_restoreDirPrefix)) continue;

      final normalizedPath = _normalizePath(subDir.path);
      final isReferenced = referencedPrefixes.any(
        (prefix) =>
            normalizedPath == prefix ||
            normalizedPath.startsWith('$prefix/'),
      );
      if (!isReferenced) {
        try {
          if (onDeleteDirectory != null) {
            await onDeleteDirectory(subDir);
          } else {
            await subDir.delete(recursive: true);
          }
        } catch (e) {
          debugPrint(
            'Storage cleanup: failed to delete restore set $subDirName: $e',
          );
        }
      }
    }
  }

  static Future<void> _cleanupOrphanPhotos(
    Directory directory,
    AppData appData, {
    Future<void> Function(File file)? onDeleteFile,
  }) async {
    final photoSetsDir = Directory('${directory.path}/photo-sets');
    if (!await photoSetsDir.exists()) return;

    final referencedPaths = <String>{};
    for (final file in appData.allPhotos) {
      referencedPaths.add(_normalizePath(file.path));
    }

    final entries = _listDirectoriesSync(photoSetsDir);
    for (final subDir in entries) {
      try {
        await _deleteOrphanPhotosInDirectory(
          subDir,
          referencedPaths,
          onDeleteFile: onDeleteFile,
        );
      } catch (e) {
        debugPrint(
          'Storage cleanup: failed to scan ${subDir.path.split(RegExp(r'[/\\]')).last} for orphans: $e',
        );
      }
    }
  }

  static Future<void> _deleteOrphanPhotosInDirectory(
    Directory directory,
    Set<String> referencedPaths, {
    Future<void> Function(File file)? onDeleteFile,
  }) async {
    final entries = _listSync(directory);
    for (final entry in entries) {
      if (entry is Directory) {
        await _deleteOrphanPhotosInDirectory(
          entry,
          referencedPaths,
          onDeleteFile: onDeleteFile,
        );
      } else if (entry is File) {
        final normalizedPath = _normalizePath(entry.path);
        if (!referencedPaths.contains(normalizedPath)) {
          try {
            if (onDeleteFile != null) {
              await onDeleteFile(entry);
            } else {
              await entry.delete();
            }
          } catch (e) {
            debugPrint(
              'Storage cleanup: failed to delete orphan photo ${entry.path.split(RegExp(r'[/\\]')).last}: $e',
            );
          }
        }
      }
    }
  }

  static List<File> _listFilesSync(Directory dir) {
    try {
      return dir.listSync().whereType<File>().toList();
    } catch (e) {
      debugPrint('Storage cleanup: failed to list files in $dir: $e');
      return <File>[];
    }
  }

  static List<Directory> _listDirectoriesSync(Directory dir) {
    try {
      return dir.listSync().whereType<Directory>().toList();
    } catch (e) {
      debugPrint('Storage cleanup: failed to list directories in $dir: $e');
      return <Directory>[];
    }
  }

  static List<FileSystemEntity> _listSync(Directory dir) {
    try {
      return dir.listSync();
    } catch (e) {
      debugPrint('Storage cleanup: failed to list entities in $dir: $e');
      return <FileSystemEntity>[];
    }
  }
}
