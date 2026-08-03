import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/photo.dart';

class MemoryManifestStore implements PendingDeletionManifestStore {
  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String? encoded) async => value = encoded;
}

Photo photo(File file) => Photo(
  id: 'photo-1',
  file: file,
  capturedAt: DateTime.utc(2026, 1, 2, 3, 4),
  location: '東京都',
  originalName: '旅.jpg',
  mimeType: 'image/jpeg',
);

AppData dataFor(Photo item) => AppData(
  trips: <Trip>[
    Trip(id: 'trip-1', title: '旅行', photos: <Photo>[item]),
  ],
  unassignedPhotos: const <Photo>[],
  prefectureStates: const <String, String>{},
);

void main() {
  late Directory root;
  late File original;
  late MemoryManifestStore store;
  late PendingDeletionManager manager;
  late AppData current;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kokoitta-pending-');
    original = File('${root.path}/original.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    store = MemoryManifestStore();
    manager = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4),
    );
    current = dataFor(photo(original));
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('stage途中失敗は元ファイルとAppDataを維持する', () async {
    var moves = 0;
    final service = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4),
      moveFile: (from, to) async {
        moves++;
        if (moves == 1) throw const FileSystemException('stage failed');
        await File(from).rename(to);
      },
    );

    await expectLater(
      service.deleteTrip(
        data: current,
        tripId: 'trip-1',
        saveData: (_) async {},
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.exists(), isTrue);
    expect(await service.loadOperations(), isEmpty);
  });

  test('保存失敗は退避ファイルを元pathへ戻しmanifestを残さない', () async {
    await expectLater(
      manager.deleteTrip(
        data: current,
        tripId: 'trip-1',
        saveData: (_) async => throw const FileSystemException('save failed'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.readAsBytes(), <int>[1, 2, 3]);
    expect(await manager.loadOperations(), isEmpty);
  });

  test('UndoはPhoto ID/metadata/所属/順序/物理内容を一致させる', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    expect(await original.exists(), isFalse);
    AppData? restored;
    await manager.undo(
      operationId: deleted.operationId,
      data: AppData.empty(),
      saveData: (value) async => restored = value,
    );
    final recovered = restored!.trips.single.photos.single;
    expect(recovered.id, 'photo-1');
    expect(recovered.capturedAt, DateTime.utc(2026, 1, 2, 3, 4));
    expect(recovered.location, '東京都');
    expect(recovered.originalName, '旅.jpg');
    expect(recovered.mimeType, 'image/jpeg');
    expect(recovered.file.path, original.path);
    expect(await original.readAsBytes(), <int>[1, 2, 3]);
    expect(await manager.loadOperations(), isEmpty);
  });

  test('Undo部分失敗はmanifestと未復元trashを保持し成功扱いにしない', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final failing = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4),
      moveFile: (from, to) async =>
          throw const FileSystemException('restore failed'),
    );
    await expectLater(
      failing.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async {},
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      (await failing.loadOperations()).single.state,
      PendingDeletionState.undoFailed,
    );
  });

  test('期限切れ・複数pending・二重実行を処理し、期限前は保持する', () async {
    final first = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final secondFile = File('${root.path}/second.jpg')
      ..writeAsBytesSync(<int>[4]);
    final secondData = AppData(
      trips: <Trip>[
        Trip(
          id: 'trip-2',
          title: '別の旅行',
          photos: <Photo>[photo(secondFile).copyWith(id: 'photo-2')],
        ),
      ],
      unassignedPhotos: const <Photo>[],
      prefectureStates: const <String, String>{},
    );
    final second = await manager.deleteTrip(
      data: secondData,
      tripId: 'trip-2',
      saveData: (_) async {},
    );
    expect(first.operationId, isNot(second.operationId));
    await expectLater(
      manager.deleteTrip(
        data: current,
        tripId: 'trip-1',
        saveData: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await manager.finalizeExpired(at: DateTime.utc(2026, 1, 2, 4))).length,
      0,
    );
    expect(await original.exists(), isFalse);
    final finalized = await manager.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 1),
    );
    expect(finalized.length, 2);
    expect(await manager.loadOperations(), isEmpty);
    expect(await secondFile.exists(), isFalse);
  });

  test('壊れたmanifestとpath traversalをfail closedで拒否する', () async {
    store.value =
        '{"version":1,"operations":[{"operationId":"x","items":[{"originalPath":"../escape","trashPath":"/tmp/x"}]}]}';
    await expectLater(
      manager.loadOperations(),
      throwsA(isA<FormatException>()),
    );
    store.value = '{not-json';
    await expectLater(
      manager.loadOperations(),
      throwsA(isA<FormatException>()),
    );
  });

  test('再起動回収はstage途中のmanifestを元へ戻す', () async {
    final op = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final raw = store.value!;
    store.value = raw.replaceFirst('"pending"', '"staged"');
    await manager.recover();
    expect(await original.exists(), isTrue);
    expect(await manager.loadOperations(), isEmpty);
    expect(op.operationId, isNotEmpty);
  });
}
