import 'dart:convert';
import 'dart:io';

import 'models.dart';

class PendingDeletion {
  const PendingDeletion({
    required this.trip,
    required this.trashDirectory,
    required this.originalPaths,
    required this.expiresAt,
  });

  final Trip trip;
  final Directory trashDirectory;
  final List<String> originalPaths;
  final DateTime expiresAt;

  Map<String, Object> toJson() => <String, Object>{
    'tripId': trip.id,
    'title': trip.title,
    'originalPaths': originalPaths,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

class PendingDeletionStore {
  const PendingDeletionStore();

  static const Duration undoWindow = Duration(seconds: 30);

  Future<PendingDeletion> stage(Trip trip, Directory root) async {
    final trash = Directory('${root.path}/pending-deletions/${trip.id}');
    await trash.create(recursive: true);
    final originalPaths = <String>[];
    try {
      for (var index = 0; index < trip.photos.length; index++) {
        final source = trip.photos[index];
        if (!await source.exists()) continue;
        final destination = File(
          '${trash.path}/$index-${source.uri.pathSegments.last}',
        );
        await source.rename(destination.path);
        originalPaths.add(source.path);
      }
      final pending = PendingDeletion(
        trip: trip,
        trashDirectory: trash,
        originalPaths: originalPaths,
        expiresAt: DateTime.now().add(undoWindow),
      );
      await File(
        '${trash.path}/manifest.json',
      ).writeAsString(jsonEncode(pending.toJson()));
      return pending;
    } catch (_) {
      await _restorePartial(trash, originalPaths);
      rethrow;
    }
  }

  Future<List<File>> restore(PendingDeletion pending) async {
    final restored = <File>[];
    for (var index = 0; index < pending.originalPaths.length; index++) {
      final original = File(pending.originalPaths[index]);
      final candidates = pending.trashDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('$index-'));
      final source = candidates.firstOrNull;
      if (source == null) continue;
      await original.parent.create(recursive: true);
      await source.rename(original.path);
      restored.add(original);
    }
    await _removeTrash(pending.trashDirectory);
    return restored;
  }

  Future<void> finalize(PendingDeletion pending) =>
      _removeTrash(pending.trashDirectory);

  Future<void> _restorePartial(Directory trash, List<String> paths) async {
    for (var index = 0; index < paths.length; index++) {
      final candidates = trash.listSync().whereType<File>().where(
        (file) => file.uri.pathSegments.last.startsWith('$index-'),
      );
      final source = candidates.firstOrNull;
      if (source == null) continue;
      final destination = File(paths[index]);
      await destination.parent.create(recursive: true);
      await source.rename(destination.path);
    }
    await _removeTrash(trash);
  }

  Future<void> _removeTrash(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

extension PendingFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
