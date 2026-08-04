import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/pending_deletion_recovery.dart';
import 'package:kokoitta_app/photo.dart';

class _FailOnNthSaveStore implements PendingDeletionManifestStore {
  _FailOnNthSaveStore({required this.failOnSave});

  String? value;
  int saveCount = 0;
  int? failOnSave;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String? encoded) async {
    saveCount += 1;
    if (saveCount == failOnSave) {
      throw const FileSystemException('pending manifest保存失敗');
    }
    value = encoded;
  }
}

void main() {
  test(
    'AppData commit後のpending manifest保存失敗はstagedとtrashを保持して再起動回復する',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'kokoitta-manifest-commit-failure-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });

      final original = File('${root.path}/original.jpg');
      await original.writeAsBytes(<int>[1, 2, 3]);
      final trip = Trip(
        id: 'trip-1',
        title: '旅行',
        photos: <Photo>[
          Photo(
            id: 'photo-1',
            file: original,
            capturedAt: DateTime.utc(2026, 8, 4, 3),
            originalName: 'original.jpg',
            mimeType: 'image/jpeg',
          ),
        ],
      );
      final initialData = AppData(
        trips: <Trip>[trip],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      );
      final store = _FailOnNthSaveStore(failOnSave: 2);
      final manager = PendingDeletionManager(
        store: store,
        trashRoot: '${root.path}/trash',
        now: () => DateTime.utc(2026, 8, 4, 4),
      );
      AppData? persistedData;

      await expectLater(
        manager.deleteTrip(
          data: initialData,
          tripId: trip.id,
          saveData: (data) async => persistedData = data,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(persistedData, isNotNull);
      expect(persistedData!.trips, isEmpty);
      expect(await original.exists(), isFalse);

      final staged = (await manager.loadOperations()).single;
      expect(staged.state, PendingDeletionState.staged);
      expect(await File(staged.items.single.trashPath).exists(), isTrue);
      expect(await File(staged.items.single.originalPath).exists(), isFalse);

      store.failOnSave = null;
      final recovered = await recoverPendingDeletions(
        manager: manager,
        data: persistedData!,
      );
      expect(recovered, hasLength(1));
      expect(recovered.single.operationId, staged.operationId);
      expect(recovered.single.state, PendingDeletionState.pending);
      expect(
        await File(recovered.single.items.single.trashPath).exists(),
        isTrue,
      );
      expect(
        await File(recovered.single.items.single.originalPath).exists(),
        isFalse,
      );

      final recoveredAgain = await recoverPendingDeletions(
        manager: manager,
        data: persistedData!,
      );
      expect(recoveredAgain, hasLength(1));
      expect(recoveredAgain.single.operationId, staged.operationId);
      expect(recoveredAgain.single.state, PendingDeletionState.pending);
    },
  );
}
