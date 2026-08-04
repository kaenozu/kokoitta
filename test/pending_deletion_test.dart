import 'dart:convert';
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

class FailingSaveManifestStore implements PendingDeletionManifestStore {
  String? value;
  bool failSaves = false;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String? encoded) async {
    if (failSaves) throw const FileSystemException('manifest保存失敗');
    value = encoded;
  }
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

  test('期限切れ後のUndoは拒否され物理復元されない', () async {
    var now = DateTime.utc(2026, 1, 2, 4);
    final mutableManager = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => now,
    );
    final deleted = await mutableManager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    now = DateTime.utc(2026, 1, 2, 4, 1); // 期限超過
    await expectLater(
      mutableManager.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(await original.exists(), isFalse);
    expect(
      (await mutableManager.loadOperations()).single.state,
      PendingDeletionState.pending,
    );
  });

  test('trashファイルが既に無い場合は削除成功としてmanifestを掃除する（冪等）', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final trashFile = File(deleted.items.single.trashPath);
    expect(await trashFile.exists(), isTrue);
    // 外部削除や前回中断でtrashファイルだけが無くなった状態を再現する。
    await trashFile.delete();
    final finalized = await manager.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 1),
    );
    expect(finalized, [deleted.operationId]);
    expect(await manager.loadOperations(), isEmpty);
  });

  test('完全削除後に二重finalizeしても追加でfinalize結果を返さない', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final first = await manager.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 1),
    );
    expect(first, [deleted.operationId]);
    expect(await manager.loadOperations(), isEmpty);
    final second = await manager.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 2),
    );
    expect(second, isEmpty);
    expect(await original.exists(), isFalse);
  });

  test('旅行IDが重複する場合は物理復元せずmanifestを再試行可能に維持する', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    // 保存済みAppDataがまだ旅行を持っている（復元競合）状況でUndoを試みる。
    await expectLater(
      manager.undo(
        operationId: deleted.operationId,
        data: current,
        saveData: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    // 物理ファイルは移動されない。
    expect(await File(deleted.items.single.originalPath).exists(), isFalse);
    expect(await File(deleted.items.single.trashPath).exists(), isTrue);
    // manifestは維持され、再試行可能なpendingのまま。
    final remaining = (await manager.loadOperations()).single;
    expect(remaining.operationId, deleted.operationId);
    expect(remaining.state, PendingDeletionState.pending);
    expect(
      remaining.items.single.physicalState,
      PendingDeletionPhysicalState.staged,
    );
  });

  test('UndoのsaveData失敗時は復元済みファイルを全てtrashへ戻す', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    await expectLater(
      manager.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async => throw const FileSystemException('save failed'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(deleted.items.single.originalPath).exists(), isFalse);
    expect(await File(deleted.items.single.trashPath).exists(), isTrue);
    final remaining = (await manager.loadOperations()).single;
    expect(remaining.state, PendingDeletionState.pending);
    expect(
      remaining.items.single.physicalState,
      PendingDeletionPhysicalState.staged,
    );
  });

  test('部分restage失敗ではitem毎のphysical stateとrollback不完全stateを保持する', () async {
    final second = File('${root.path}/second.jpg')..writeAsBytesSync(<int>[4]);
    final deleted = await manager.deleteTrip(
      data: _twoPhotoData(original, second),
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final failing = _deRestageManager(
      deleted.items[1].originalPath,
      store,
      '${root.path}/trash',
    );
    await expectLater(
      failing.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async => throw const FileSystemException('save failed'),
      ),
      throwsA(isA<StateError>()),
    );
    final remaining = (await failing.loadOperations()).single;
    expect(remaining.state, PendingDeletionState.undoRollbackFailed);
    // item1は再stage成功 → staged（trashに存在）。
    expect(
      remaining.items[0].physicalState,
      PendingDeletionPhysicalState.staged,
    );
    expect(await File(remaining.items[0].originalPath).exists(), isFalse);
    expect(await File(remaining.items[0].trashPath).exists(), isTrue);
    // item2は再stage失敗 → restoredのまま（originalに存在）。
    expect(
      remaining.items[1].physicalState,
      PendingDeletionPhysicalState.restored,
    );
    expect(await File(remaining.items[1].originalPath).exists(), isTrue);
    expect(await File(remaining.items[1].trashPath).exists(), isFalse);
  });

  test('undoCommitFailedをfinalizeExpiredが自動確定削除しない', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    store.value = store.value!.replaceFirst('"pending"', '"undoCommitFailed"');
    final finalized = await manager.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 1),
    );
    expect(finalized, isEmpty);
    final remaining = (await manager.loadOperations()).single;
    expect(remaining.operationId, deleted.operationId);
    expect(remaining.state, PendingDeletionState.undoCommitFailed);
    expect(await File(remaining.items.single.trashPath).exists(), isTrue);
  });

  test('restored+trash欠損をdeleted扱いしない', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final item = deleted.items.single;
    // 中断されたUndo（復元phase完了後）を再現: ファイルはoriginalへ戻り、
    // manifest上のitemをrestoredへ書き換える。
    await File(item.trashPath).rename(item.originalPath);
    final raw = jsonDecode(store.value!) as Map<String, dynamic>;
    final operation =
        (raw['operations'] as List).single as Map<String, dynamic>;
    (operation['items'] as List).single['physicalState'] = 'restored';
    store.value = jsonEncode(raw);
    final finalized = await manager.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 1),
    );
    expect(finalized, isEmpty);
    // originalに復元されたファイルは削除されず、manifestにも保持される。
    expect(await File(item.originalPath).exists(), isTrue);
    final remaining = (await manager.loadOperations()).single;
    expect(
      remaining.items.single.physicalState,
      PendingDeletionPhysicalState.restored,
    );
  });

  test('再起動後もundoCommitFailedはfail-closedでmanifestに保持される', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    store.value = store.value!.replaceFirst('"pending"', '"undoCommitFailed"');
    final restarted = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4, 1),
    );
    await restarted.recover();
    final remaining = (await restarted.loadOperations()).single;
    expect(remaining.operationId, deleted.operationId);
    expect(remaining.state, PendingDeletionState.undoCommitFailed);
    // 自動確定削除されずtrashも残る。
    expect(await File(remaining.items.single.trashPath).exists(), isTrue);
  });

  test('originalとtrashの両方にファイルがある場合はrecoverでfail-closed', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    store.value = store.value!.replaceFirst('"pending"', '"staged"');
    // 外部操作でoriginalにもファイルが再作成された状態を再現する。
    File(deleted.items.single.originalPath).writeAsBytesSync(<int>[9]);
    await manager.recover();
    final remaining = (await manager.loadOperations()).single;
    expect(remaining.operationId, deleted.operationId);
    // どちらのファイルも変更されない。
    expect(await File(deleted.items.single.originalPath).exists(), isTrue);
    expect(await File(deleted.items.single.trashPath).exists(), isTrue);
  });

  test('originalとtrashの両方が無い場合はrecoverでfail-closed', () async {
    final deleted = await manager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    store.value = store.value!.replaceFirst('"pending"', '"staged"');
    await File(deleted.items.single.trashPath).delete();
    await manager.recover();
    final remaining = (await manager.loadOperations()).single;
    expect(remaining.operationId, deleted.operationId);
    expect(await File(deleted.items.single.originalPath).exists(), isFalse);
    expect(await File(deleted.items.single.trashPath).exists(), isFalse);
  });

  test('manifest保存失敗時は既存manifestを消さない', () async {
    final failingStore = FailingSaveManifestStore();
    final localManager = PendingDeletionManager(
      store: failingStore,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4),
    );
    final deleted = await localManager.deleteTrip(
      data: current,
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    failingStore.failSaves = true;
    await expectLater(
      localManager.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async => throw const FileSystemException('save failed'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    // 既存manifestは消えず、ファイルはtrashへ戻ったまま一致している。
    expect(failingStore.value, isNotNull);
    final remaining = (await localManager.loadOperations()).single;
    expect(remaining.operationId, deleted.operationId);
    expect(
      remaining.items.single.physicalState,
      PendingDeletionPhysicalState.staged,
    );
    expect(await File(remaining.items.single.trashPath).exists(), isTrue);
  });

  test('複数写真の一部rollback失敗はmanifest保持と診断情報を含む', () async {
    final second = File('${root.path}/second.jpg')..writeAsBytesSync(<int>[4]);
    final third = File('${root.path}/third.jpg')..writeAsBytesSync(<int>[5]);
    final deleted = await manager.deleteTrip(
      data: AppData(
        trips: <Trip>[
          Trip(
            id: 'trip-1',
            title: '旅行',
            photos: <Photo>[
              photo(original),
              photo(second).copyWith(id: 'photo-2'),
              photo(third).copyWith(id: 'photo-3'),
            ],
          ),
        ],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final failingPaths = <String>{
      deleted.items[1].originalPath,
      deleted.items[2].originalPath,
    };
    final failing = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4),
      moveFile: (from, to) async {
        if (failingPaths.contains(from)) {
          throw const FileSystemException('rollback failed');
        }
        await File(from).rename(to);
      },
    );
    Object? caught;
    try {
      await failing.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async => throw const FileSystemException('save failed'),
      );
    } catch (error) {
      caught = error;
    }
    expect(caught, isA<StateError>());
    expect(caught.toString(), contains('save failed'));
    expect(caught.toString(), contains('rollbackで2件失敗'));
    final remaining = (await failing.loadOperations()).single;
    expect(remaining.state, PendingDeletionState.undoRollbackFailed);
    expect(
      remaining.items[0].physicalState,
      PendingDeletionPhysicalState.staged,
    );
    expect(
      remaining.items[1].physicalState,
      PendingDeletionPhysicalState.restored,
    );
    expect(
      remaining.items[2].physicalState,
      PendingDeletionPhysicalState.restored,
    );
  });

  test('部分rollback後も各ファイルはoriginalかtrashの片方だけに存在する', () async {
    final second = File('${root.path}/second.jpg')..writeAsBytesSync(<int>[4]);
    final deleted = await manager.deleteTrip(
      data: _twoPhotoData(original, second),
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final failing = _deRestageManager(
      deleted.items[1].originalPath,
      store,
      '${root.path}/trash',
    );
    try {
      await failing.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async => throw const FileSystemException('save failed'),
      );
    } catch (_) {
      // rollback不完全で失敗する想定。
    }
    final remaining = (await failing.loadOperations()).single;
    // 各itemでoriginal xor trashが成立し、重複コピーや消失がない。
    final present = <String>[];
    for (final item in remaining.items) {
      final originalExists = await File(item.originalPath).exists();
      final trashExists = await File(item.trashPath).exists();
      expect(
        originalExists,
        isNot(trashExists),
        reason: 'item ${item.photo.id}',
      );
      if (originalExists) present.add(item.originalPath);
      if (trashExists) present.add(item.trashPath);
    }
    expect(present.length, remaining.items.length);
    // trash配下にはstaged itemのtrashファイルだけが残る。
    final trashFiles = await Directory('${root.path}/trash')
        .list(recursive: true)
        .where((entity) => entity is File)
        .map((entity) => _normalizePath((entity as File).path))
        .toSet();
    final expectedTrash = remaining.items
        .where(
          (item) => item.physicalState == PendingDeletionPhysicalState.staged,
        )
        .map((item) => _normalizePath(item.trashPath))
        .toSet();
    expect(trashFiles, expectedTrash);
  });

  test('rollback不完全operationはfinalizeと再起動後もmanifestに残る', () async {
    final second = File('${root.path}/second.jpg')..writeAsBytesSync(<int>[4]);
    final deleted = await manager.deleteTrip(
      data: _twoPhotoData(original, second),
      tripId: 'trip-1',
      saveData: (_) async {},
    );
    final failing = _deRestageManager(
      deleted.items[1].originalPath,
      store,
      '${root.path}/trash',
    );
    try {
      await failing.undo(
        operationId: deleted.operationId,
        data: AppData.empty(),
        saveData: (_) async => throw const FileSystemException('save failed'),
      );
    } catch (_) {
      // rollback不完全で失敗する想定。
    }
    // 期限超過してもfinalizeExpiredでoperationは消えない。
    final finalized = await failing.finalizeExpired(
      at: DateTime.utc(2026, 1, 2, 4, 1),
    );
    expect(finalized, isEmpty);
    expect(
      (await failing.loadOperations()).single.operationId,
      deleted.operationId,
    );
    // 再起動相当のrecoverでも消えず、復元済みitemも保持される。
    final restarted = PendingDeletionManager(
      store: store,
      trashRoot: '${root.path}/trash',
      now: () => DateTime.utc(2026, 1, 2, 4, 1),
    );
    await restarted.recover();
    final afterRecover = (await restarted.loadOperations()).single;
    expect(afterRecover.operationId, deleted.operationId);
    expect(
      afterRecover.items[1].physicalState,
      PendingDeletionPhysicalState.restored,
    );
    expect(await File(afterRecover.items[1].originalPath).exists(), isTrue);
  });
}

AppData _twoPhotoData(File original, File second) => AppData(
  trips: <Trip>[
    Trip(
      id: 'trip-1',
      title: '旅行',
      photos: <Photo>[
        photo(original),
        photo(second).copyWith(id: 'photo-2'),
      ],
    ),
  ],
  unassignedPhotos: const <Photo>[],
  prefectureStates: const <String, String>{},
);

/// Windows/macOS/Linux間のパス区切り差異を吸収して比較する。
String _normalizePath(String path) => path.replaceAll('\\', '/');

/// second itemの再stage（original→trash）だけを失敗させるUndo用マネージャ。
PendingDeletionManager _deRestageManager(
  String secondOriginalPath,
  MemoryManifestStore store,
  String trashRoot,
) => PendingDeletionManager(
  store: store,
  trashRoot: trashRoot,
  now: () => DateTime.utc(2026, 1, 2, 4),
  moveFile: (from, to) async {
    if (from == secondOriginalPath) {
      throw const FileSystemException('restage failed');
    }
    await File(from).rename(to);
  },
);
