import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/pending_deletion_recovery.dart';
import 'package:kokoitta_app/photo.dart';

class _MemoryManifestStore implements PendingDeletionManifestStore {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String? encoded) async => value = encoded;
}

void main() {
  test('AppData commit後にstagedが残った場合はpendingへ進めて写真をtrashに維持する', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.dispose);
    await fixture.saveManifest();

    final remaining = await recoverPendingDeletions(
      manager: fixture.manager,
      data: AppData.empty(),
    );

    expect(remaining, hasLength(1));
    expect(remaining.single.operationId, fixture.operation.operationId);
    expect(remaining.single.state, PendingDeletionState.pending);
    expect(await fixture.originals.single.exists(), isFalse);
    expect(await fixture.trashFiles.single.exists(), isTrue);
  });

  test('AppData commit前にstagedが残った場合は写真を復元してmanifestを除去する', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.dispose);
    await fixture.saveManifest();

    final remaining = await recoverPendingDeletions(
      manager: fixture.manager,
      data: fixture.dataWithTrip,
    );

    expect(remaining, isEmpty);
    expect(await fixture.manager.loadOperations(), isEmpty);
    expect(await fixture.originals.single.readAsBytes(), <int>[1]);
    expect(await fixture.trashFiles.single.exists(), isFalse);
  });

  test('復元rename完了後・manifest反映前の中断を次回回復で完了する', () async {
    final fixture = await _RecoveryFixture.create();
    addTearDown(fixture.dispose);
    await fixture.saveManifest();
    await fixture.trashFiles.single.rename(fixture.originals.single.path);

    final remaining = await recoverPendingDeletions(
      manager: fixture.manager,
      data: fixture.dataWithTrip,
    );

    expect(remaining, isEmpty);
    expect(await fixture.originals.single.readAsBytes(), <int>[1]);
    expect(await fixture.trashFiles.single.exists(), isFalse);
  });

  test('originalとtrashが両方ある曖昧状態は変更せずstaged manifestを保持する', () async {
    final fixture = await _RecoveryFixture.create(createOriginal: true);
    addTearDown(fixture.dispose);
    await fixture.saveManifest();

    final remaining = await recoverPendingDeletions(
      manager: fixture.manager,
      data: AppData.empty(),
    );

    expect(remaining, hasLength(1));
    expect(remaining.single.state, PendingDeletionState.staged);
    expect(await fixture.originals.single.readAsBytes(), <int>[9]);
    expect(await fixture.trashFiles.single.readAsBytes(), <int>[1]);
  });

  test('複数写真の回復途中失敗をmanifestから再開して全写真を復元する', () async {
    final fixture = await _RecoveryFixture.create(photoCount: 2);
    addTearDown(fixture.dispose);
    await fixture.saveManifest();
    var moveCount = 0;
    final failingManager = PendingDeletionManager(
      store: fixture.store,
      trashRoot: fixture.trashRoot,
      now: fixture.now,
      moveFile: (from, to) async {
        moveCount += 1;
        if (moveCount == 2) {
          throw const FileSystemException('回復途中失敗');
        }
        await File(from).rename(to);
      },
    );

    await expectLater(
      recoverPendingDeletions(
        manager: failingManager,
        data: fixture.dataWithTrip,
      ),
      throwsA(isA<FileSystemException>()),
    );

    final interrupted = (await fixture.manager.loadOperations()).single;
    expect(interrupted.state, PendingDeletionState.staged);
    expect(
      interrupted.items.where(
        (item) =>
            item.physicalState == PendingDeletionPhysicalState.restored,
      ),
      hasLength(1),
    );
    expect(
      interrupted.items.where(
        (item) => item.physicalState == PendingDeletionPhysicalState.staged,
      ),
      hasLength(1),
    );

    final remaining = await recoverPendingDeletions(
      manager: fixture.manager,
      data: fixture.dataWithTrip,
    );

    expect(remaining, isEmpty);
    for (var index = 0; index < fixture.originals.length; index++) {
      expect(await fixture.originals[index].readAsBytes(), <int>[index + 1]);
      expect(await fixture.trashFiles[index].exists(), isFalse);
    }
  });
}

class _RecoveryFixture {
  _RecoveryFixture({
    required this.root,
    required this.originals,
    required this.trashFiles,
    required this.trip,
    required this.operation,
    required this.store,
    required this.manager,
    required this.now,
  });

  final Directory root;
  final List<File> originals;
  final List<File> trashFiles;
  final Trip trip;
  final PendingDeletionOperation operation;
  final _MemoryManifestStore store;
  final PendingDeletionManager manager;
  final DateTime Function() now;

  String get trashRoot => '${root.path}/trash';

  AppData get dataWithTrip => AppData(
    trips: <Trip>[trip],
    unassignedPhotos: const <Photo>[],
    prefectureStates: const <String, String>{},
  );

  static Future<_RecoveryFixture> create({
    bool createOriginal = false,
    int photoCount = 1,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'kokoitta-startup-recovery-',
    );
    final originals = <File>[];
    final trashFiles = <File>[];
    final photos = <Photo>[];
    final items = <PendingDeletionItem>[];

    for (var index = 0; index < photoCount; index++) {
      final original = File('${root.path}/original-$index.jpg');
      if (createOriginal) await original.writeAsBytes(<int>[9 + index]);
      final trash = File(
        '${root.path}/trash/delete-trip-1/$index-original-$index.jpg',
      );
      await trash.parent.create(recursive: true);
      await trash.writeAsBytes(<int>[index + 1]);
      final photo = Photo(
        id: 'photo-$index',
        file: original,
        capturedAt: DateTime.utc(2026, 8, 4, 3, index),
        originalName: 'original-$index.jpg',
        mimeType: 'image/jpeg',
      );
      originals.add(original);
      trashFiles.add(trash);
      photos.add(photo);
      items.add(
        PendingDeletionItem(
          photo: photo,
          tripId: 'trip-1',
          tripIndex: 0,
          photoIndex: index,
          originalPath: original.path,
          trashPath: trash.path,
          physicalState: PendingDeletionPhysicalState.staged,
        ),
      );
    }

    final trip = Trip(id: 'trip-1', title: '旅行', photos: photos);
    final operation = PendingDeletionOperation(
      operationId: 'delete-trip-1',
      trip: trip,
      createdAt: DateTime.utc(2026, 8, 4, 3),
      expiresAt: DateTime.utc(2100, 1, 1),
      state: PendingDeletionState.staged,
      items: items,
    );
    final store = _MemoryManifestStore();
    DateTime currentTime() => DateTime.utc(2026, 8, 4, 4);
    final manager = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: currentTime,
    );
    return _RecoveryFixture(
      root: root,
      originals: originals,
      trashFiles: trashFiles,
      trip: trip,
      operation: operation,
      store: store,
      manager: manager,
      now: currentTime,
    );
  }

  Future<void> saveManifest() => store.save(
    jsonEncode(<String, Object?>{
      'version': 1,
      'operations': <Map<String, Object?>>[operation.toJson()],
    }),
  );

  Future<void> dispose() async {
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windowsでファイルハンドルが残る場合はベストエフォートで後始末する。
    }
  }
}
