import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _noopCleanup(AppData data) async {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('AppData commit後にstagedが残った場合はpendingへ進めて写真をtrashに維持する', (
    tester,
  ) async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    await TripStore().save(AppData.empty());
    await fixture.saveManifest();

    await tester.pumpWidget(
      KokoittaApp(
        cleanupRunner: _noopCleanup,
        pendingDeletionBuilder: () => fixture.manager,
      ),
    );

    await tester.runAsync(() async {
      await _waitForState(
        fixture.manager,
        PendingDeletionState.pending,
      );
    });

    final remaining = (await fixture.manager.loadOperations()).single;
    expect(remaining.operationId, fixture.operation.operationId);
    expect(remaining.state, PendingDeletionState.pending);
    expect(await fixture.original.exists(), isFalse);
    expect(await fixture.trash.exists(), isTrue);
  });

  testWidgets('AppData commit前にstagedが残った場合は写真を復元してmanifestを除去する', (
    tester,
  ) async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    await TripStore().save(
      AppData(
        trips: <Trip>[fixture.trip],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    await fixture.saveManifest();

    await tester.pumpWidget(
      KokoittaApp(
        cleanupRunner: _noopCleanup,
        pendingDeletionBuilder: () => fixture.manager,
      ),
    );

    await tester.runAsync(() async {
      await _waitForNoOperations(fixture.manager);
    });

    expect(await fixture.manager.loadOperations(), isEmpty);
    expect(await fixture.original.exists(), isTrue);
    expect(await fixture.original.readAsBytes(), <int>[1, 2, 3]);
    expect(await fixture.trash.exists(), isFalse);
  });

  testWidgets('復元rename完了後・manifest反映前の中断を次回起動で完了する', (
    tester,
  ) async {
    final fixture = await _createFixture();
    addTearDown(fixture.dispose);
    await TripStore().save(
      AppData(
        trips: <Trip>[fixture.trip],
        unassignedPhotos: const <Photo>[],
        prefectureStates: const <String, String>{},
      ),
    );
    await fixture.saveManifest();
    await fixture.trash.rename(fixture.original.path);

    await tester.pumpWidget(
      KokoittaApp(
        cleanupRunner: _noopCleanup,
        pendingDeletionBuilder: () => fixture.manager,
      ),
    );

    await tester.runAsync(() async {
      await _waitForNoOperations(fixture.manager);
    });

    expect(await fixture.manager.loadOperations(), isEmpty);
    expect(await fixture.original.exists(), isTrue);
    expect(await fixture.original.readAsBytes(), <int>[1, 2, 3]);
    expect(await fixture.trash.exists(), isFalse);
  });

  testWidgets('originalとtrashが両方ある曖昧状態は変更せずstaged manifestを保持する', (
    tester,
  ) async {
    final fixture = await _createFixture(createOriginal: true);
    addTearDown(fixture.dispose);
    await TripStore().save(AppData.empty());
    await fixture.saveManifest();

    await tester.pumpWidget(
      KokoittaApp(
        cleanupRunner: _noopCleanup,
        pendingDeletionBuilder: () => fixture.manager,
      ),
    );

    await tester.runAsync(() async {
      await _waitUntilLoaded(tester);
    });

    final remaining = (await fixture.manager.loadOperations()).single;
    expect(remaining.state, PendingDeletionState.staged);
    expect(await fixture.original.exists(), isTrue);
    expect(await fixture.trash.exists(), isTrue);
  });
}

Future<void> _waitForState(
  PendingDeletionManager manager,
  PendingDeletionState expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final operations = await manager.loadOperations();
    if (operations.length == 1 && operations.single.state == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('pending deletionが${expected.name}へ遷移しませんでした');
}

Future<void> _waitForNoOperations(PendingDeletionManager manager) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if ((await manager.loadOperations()).isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('pending deletion manifestが除去されませんでした');
}

Future<void> _waitUntilLoaded(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline) &&
      tester.widgetList(find.text('写真を追加')).isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump();
  }
  expect(find.text('写真を追加'), findsOneWidget);
}

Future<_RecoveryFixture> _createFixture({bool createOriginal = false}) async {
  final root = await Directory.systemTemp.createTemp(
    'kokoitta-startup-recovery-',
  );
  final original = File('${root.path}/original.jpg');
  if (createOriginal) await original.writeAsBytes(<int>[9]);
  final trash = File('${root.path}/trash/delete-trip-1/0-original.jpg');
  await trash.parent.create(recursive: true);
  await trash.writeAsBytes(<int>[1, 2, 3]);

  final photo = Photo(
    id: 'photo-1',
    file: original,
    capturedAt: DateTime.utc(2026, 8, 4, 3),
    originalName: 'original.jpg',
    mimeType: 'image/jpeg',
  );
  final trip = Trip(id: 'trip-1', title: '旅行', photos: <Photo>[photo]);
  final operation = PendingDeletionOperation(
    operationId: 'delete-trip-1',
    trip: trip,
    createdAt: DateTime.utc(2026, 8, 4, 3),
    expiresAt: DateTime.utc(2100, 1, 1),
    state: PendingDeletionState.staged,
    items: <PendingDeletionItem>[
      PendingDeletionItem(
        photo: photo,
        tripId: trip.id,
        tripIndex: 0,
        photoIndex: 0,
        originalPath: original.path,
        trashPath: trash.path,
        physicalState: PendingDeletionPhysicalState.staged,
      ),
    ],
  );
  final store = SharedPreferencesPendingDeletionStore();
  final manager = PendingDeletionManager(
    store: store,
    trashRoot: '${root.path}/trash',
    now: () => DateTime.utc(2026, 8, 4, 4),
  );
  return _RecoveryFixture(
    root: root,
    original: original,
    trash: trash,
    trip: trip,
    operation: operation,
    store: store,
    manager: manager,
  );
}

class _RecoveryFixture {
  _RecoveryFixture({
    required this.root,
    required this.original,
    required this.trash,
    required this.trip,
    required this.operation,
    required this.store,
    required this.manager,
  });

  final Directory root;
  final File original;
  final File trash;
  final Trip trip;
  final PendingDeletionOperation operation;
  final SharedPreferencesPendingDeletionStore store;
  final PendingDeletionManager manager;

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
