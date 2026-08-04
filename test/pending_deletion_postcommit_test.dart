import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/pending_deletion_recovery.dart';
import 'package:kokoitta_app/photo.dart';

class _FailOnSaveStore implements PendingDeletionManifestStore {
  _FailOnSaveStore(this.failOnCalls);

  final Set<int> failOnCalls;
  String? value;
  int saveCalls = 0;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String? encoded) async {
    saveCalls += 1;
    if (failOnCalls.contains(saveCalls)) {
      throw FileSystemException('manifest save $saveCalls failed');
    }
    value = encoded;
  }
}

Photo _photo(String id, File file) => Photo(
  id: id,
  file: file,
  capturedAt: DateTime.utc(2026, 8, 4, 4),
  originalName: '$id.jpg',
  mimeType: 'image/jpeg',
);

void main() {
  test(
    'post-commit pending save failure preserves staged recovery manifest',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'kokoitta-postcommit-manifest-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final original = File('${root.path}/original.jpg')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final trip = Trip(
        id: 'trip-1',
        title: '旅行',
        photos: <Photo>[_photo('photo-1', original)],
      );
      final initial = AppData(
        trips: <Trip>[trip],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      );
      final store = _FailOnSaveStore(<int>{2});
      final manager = PendingDeletionManager(
        store: store,
        trashRoot: '${root.path}/trash',
        now: () => DateTime.utc(2026, 8, 4, 5),
      );
      AppData committed = initial;

      await expectLater(
        manager.deleteTrip(
          data: initial,
          tripId: trip.id,
          saveData: (value) async => committed = value,
        ),
        throwsA(isA<StateError>()),
      );

      expect(committed.trips, isEmpty);
      final staged = (await manager.loadOperations()).single;
      expect(staged.state, PendingDeletionState.staged);
      expect(await File(staged.items.single.originalPath).exists(), isFalse);
      expect(await File(staged.items.single.trashPath).exists(), isTrue);

      final firstRecovery = await recoverPendingDeletions(
        manager: manager,
        data: committed,
      );
      expect(firstRecovery.single.state, PendingDeletionState.pending);
      expect(await File(staged.items.single.originalPath).exists(), isFalse);
      expect(await File(staged.items.single.trashPath).exists(), isTrue);

      final secondRecovery = await recoverPendingDeletions(
        manager: manager,
        data: committed,
      );
      expect(secondRecovery.single.state, PendingDeletionState.pending);
      expect(secondRecovery.single.operationId, staged.operationId);
    },
  );

  test('zero-photo trip undo restores the original trip order', () async {
    final root = await Directory.systemTemp.createTemp(
      'kokoitta-empty-trip-undo-',
    );
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final store = _FailOnSaveStore(const <int>{});
    final manager = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 8, 4, 5),
    );
    final first = Trip(id: 'trip-1', title: '先', photos: const <Photo>[]);
    final empty = Trip(id: 'trip-2', title: '空', photos: const <Photo>[]);
    final last = Trip(id: 'trip-3', title: '後', photos: const <Photo>[]);
    final initial = AppData(
      trips: <Trip>[first, empty, last],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );
    AppData deletedData = initial;

    final operation = await manager.deleteTrip(
      data: initial,
      tripId: empty.id,
      saveData: (value) async => deletedData = value,
    );
    expect(operation.items, isEmpty);
    expect(operation.tripIndex, 1);
    expect(deletedData.trips.map((trip) => trip.id), ['trip-1', 'trip-3']);

    AppData? restored;
    await manager.undo(
      operationId: operation.operationId,
      data: deletedData,
      saveData: (value) async => restored = value,
    );

    expect(
      restored!.trips.map((trip) => trip.id),
      ['trip-1', 'trip-2', 'trip-3'],
    );
    expect(restored!.trips[1].photos, isEmpty);
    expect(await manager.loadOperations(), isEmpty);
  });
}
