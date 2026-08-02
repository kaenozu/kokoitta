import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/import_progress.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

final List<int> _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<void> _noopCleanup(AppData data) async {}

class _ControlledPrefsStore extends InMemorySharedPreferencesStore {
  _ControlledPrefsStore({this.failRollbackSave = false}) : super.empty();

  final bool failRollbackSave;
  Completer<void>? release;
  final Completer<void> importSaveStarted = Completer<void>();
  int dataKeyWrites = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final gate = release;
    if (gate != null && !importSaveStarted.isCompleted) {
      importSaveStarted.complete();
    }
    if (gate != null) await gate.future;
    if (gate != null && key == 'flutter.${TripStore.dataKey}') {
      dataKeyWrites += 1;
      if (failRollbackSave && dataKeyWrites == 2) {
        throw StateError('rollback保存失敗のテスト用');
      }
    }
    return super.setValue(valueType, key, value);
  }
}

Map<String, Object?> _importResultEvent({
  required String requestId,
  required String path,
}) {
  return <String, Object?>{
    'requestId': requestId,
    'phase': 'completed',
    'processed': 1,
    'total': 1,
    'succeeded': 1,
    'failed': 0,
    'terminal': true,
    'successes': <Map<String, Object?>>[
      <String, Object?>{
        'path': path,
        'name': 'shared.jpg',
        'mimeType': 'image/jpeg',
        'size': 1,
      },
    ],
    'failures': <Map<String, Object?>>[],
  };
}

void _mockPathProvider(Directory documentsDir) {
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return documentsDir.path;
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
  });
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

Future<void> _waitForSaveStart(
  _ControlledPrefsStore store, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (store.importSaveStarted.isCompleted) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('import commitの開始を待機中にタイムアウトしました');
}

Future<ImportEvent> _waitForTerminal(
  List<ImportEvent> events, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final terminal = events.where((event) => event.isTerminal).lastOrNull;
    if (terminal != null) return terminal;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('terminal import eventを待機中にタイムアウトしました');
}

Future<void> _sendImportResult(
  WidgetTester tester,
  MethodChannel channel,
  Map<String, Object?> arguments,
) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('importResult', arguments),
        ),
        null,
      );
  await tester.pump();
}

Future<List<FileSystemEntity>> _copiedPhotos(Directory documentsDir) async {
  final photosDir = Directory('${documentsDir.path}/photos');
  if (!await photosDir.exists()) return const <FileSystemEntity>[];
  return photosDir.list().toList();
}

int _tripCount(String raw) =>
    ((jsonDecode(raw) as Map<String, dynamic>)['trips'] as List).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kaenozu.kokoitta/share');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSharedUris') {
            return <String, Object?>{
              'successes': <Object?>[],
              'failures': <Object?>[],
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('commit後キャンセルの保存復元失敗をterminal failureとして通知する', (
    tester,
  ) async {
    final sourceDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('kokoitta-cancel-source'),
    ))!;
    final documentsDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('kokoitta-cancel-docs'),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
        if (await documentsDir.exists()) {
          await documentsDir.delete(recursive: true);
        }
      });
    });
    final source = File('${sourceDir.path}/shared.jpg');
    await tester.runAsync(() => source.writeAsBytes(_pngBytes));
    _mockPathProvider(documentsDir);

    final store = _ControlledPrefsStore(failRollbackSave: true);
    SharedPreferencesStorePlatform.instance = store;
    final events = <ImportEvent>[];

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          onImportEvent: events.add,
        ),
      );
      await _waitUntilLoaded(tester);
      store.release = Completer<void>();
      await _sendImportResult(
        tester,
        channel,
        _importResultEvent(
          requestId: 'rollback-save-failure',
          path: source.path,
        ),
      );
      await _waitForSaveStart(store, timeout: const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      expect(events.where((event) => event.isTerminal), isEmpty);
      store.release!.complete();
    });

    final terminal = (await tester.runAsync(
      () => _waitForTerminal(events, timeout: const Duration(seconds: 10)),
    ))!;
    await tester.pump(const Duration(milliseconds: 100));

    expect(terminal.phase, ImportPhase.failed);
    expect(terminal.failures.single.errorCode, 'rollback_restore_failed');
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(TripStore.dataKey);
    expect(raw, isNotNull);
    expect(_tripCount(raw!), 1);
    expect(
      await tester.runAsync(() => _copiedPhotos(documentsDir)),
      hasLength(1),
    );
    expect(find.text('共有からのおでかけ 1'), findsOneWidget);
    expect(find.textContaining('取り消しに失敗しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('commit後キャンセルの写真削除失敗をterminal failureとして通知する', (
    tester,
  ) async {
    final sourceDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('kokoitta-cancel-source'),
    ))!;
    final documentsDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('kokoitta-cancel-docs'),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
        if (await documentsDir.exists()) {
          await documentsDir.delete(recursive: true);
        }
      });
    });
    final source = File('${sourceDir.path}/shared.jpg');
    await tester.runAsync(() => source.writeAsBytes(_pngBytes));
    _mockPathProvider(documentsDir);

    final store = _ControlledPrefsStore();
    SharedPreferencesStorePlatform.instance = store;
    final events = <ImportEvent>[];
    final deleteRequests = <List<Photo>>[];

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          photoDeleteRunner: (photos) async {
            deleteRequests.add(photos.toList(growable: false));
            return 1;
          },
          onImportEvent: events.add,
        ),
      );
      await _waitUntilLoaded(tester);
      store.release = Completer<void>();
      await _sendImportResult(
        tester,
        channel,
        _importResultEvent(
          requestId: 'rollback-delete-failure',
          path: source.path,
        ),
      );
      await _waitForSaveStart(store, timeout: const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      expect(events.where((event) => event.isTerminal), isEmpty);
      store.release!.complete();
    });

    final terminal = (await tester.runAsync(
      () => _waitForTerminal(events, timeout: const Duration(seconds: 10)),
    ))!;
    await tester.pump(const Duration(milliseconds: 100));

    expect(terminal.phase, ImportPhase.failed);
    expect(terminal.failures.single.errorCode, 'rollback_cleanup_failed');
    expect(deleteRequests, hasLength(1));
    expect(deleteRequests.single, hasLength(1));
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(TripStore.dataKey);
    expect(raw, isNotNull);
    expect(_tripCount(raw!), 0);
    expect(
      await tester.runAsync(() => _copiedPhotos(documentsDir)),
      hasLength(1),
    );
    expect(find.text('共有からのおでかけ 1'), findsNothing);
    expect(find.textContaining('取り消しに失敗しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    var value = iterator.current;
    while (iterator.moveNext()) {
      value = iterator.current;
    }
    return value;
  }
}
