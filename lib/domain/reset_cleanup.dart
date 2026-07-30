import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ResetCleanup {
  const ResetCleanup();

  static const String _pendingDeletionsFile = 'pending_deletions.json';
  static const String _failedCleanupFile = 'failed_cleanup.json';

  static Future<void> migratePendingDeletions({
    Directory? documentsDirectory,
  }) async {
    try {
      final directory =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      final pendingFile = File('${directory.path}/$_pendingDeletionsFile');
      if (!await pendingFile.exists()) return;

      final content = await pendingFile.readAsString();
      final pendingPaths = _parsePendingDeletions(content);
      if (pendingPaths.isEmpty) {
        await pendingFile.delete();
        return;
      }

      final failedFile = File('${directory.path}/$_failedCleanupFile');
      final existingFailed = <String>[];
      if (await failedFile.exists()) {
        existingFailed.addAll(_parsePendingDeletions(
          await failedFile.readAsString(),
        ));
      }

      final backupDir = Directory('${directory.path}/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final retained = <String>[];
      for (final path in pendingPaths) {
        final file = File(path);
        if (await file.exists()) {
          final target =
              '${backupDir.path}/${_retryFileName(path, existingFailed.length + retained.length)}';
          try {
            await file.copy(target);
            retained.add(path);
          } catch (e) {
            debugPrint(
              'ResetCleanup: failed to write retry file for $path: $e',
            );
          }
        }
      }

      if (retained.isNotEmpty) {
        await failedFile.writeAsString(
          _serializePendingDeletions([...existingFailed, ...retained]),
        );
      }

      await pendingFile.delete();
    } catch (e) {
      debugPrint('ResetCleanup: migration failed: $e');
    }
  }

  static String _retryFileName(String originalPath, int index) {
    final base = originalPath.split(RegExp(r'[/\\]')).last;
    final dotIndex = base.lastIndexOf('.');
    final name = dotIndex >= 0 ? base.substring(0, dotIndex) : base;
    final ext = dotIndex >= 0 ? base.substring(dotIndex) : '';
    return '$name-retry-$index$ext';
  }

  static List<String> _parsePendingDeletions(String content) {
    try {
      return content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  static String _serializePendingDeletions(List<String> paths) {
    return paths.join('\n');
  }

  static Future<void> cleanupFailedCleanup({
    Directory? documentsDirectory,
    Future<void> Function(File file)? onDeleteFile,
  }) async {
    try {
      final directory =
          documentsDirectory ?? await getApplicationDocumentsDirectory();
      final failedFile = File('${directory.path}/$_failedCleanupFile');
      if (!await failedFile.exists()) return;

      final paths = _parsePendingDeletions(
        await failedFile.readAsString(),
      );
      if (paths.isEmpty) {
        await failedFile.delete();
        return;
      }

      final remaining = <String>[];
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) {
          remaining.add(path);
          continue;
        }
        try {
          if (onDeleteFile != null) {
            await onDeleteFile(file);
          } else {
            await file.delete();
          }
        } catch (e) {
          debugPrint(
            'ResetCleanup: failed to delete $path: $e',
          );
          remaining.add(path);
        }
      }

      if (remaining.isNotEmpty) {
        await failedFile.writeAsString(
          _serializePendingDeletions(remaining),
        );
      } else {
        await failedFile.delete();
      }
    } catch (e) {
      debugPrint('ResetCleanup: failed cleanup failed: $e');
    }
  }
}