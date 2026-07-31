import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareChannel = MethodChannel('com.kaenozu.kokoitta/share');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempDir;
  late Directory photosDir;
  late File photoFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kokoitta-delete-undo');
    photosDir = Directory('${tempDir.path}/photos');
    await photosDir.create(recursive: true);
    photoFile = File('${photosDir.path}/photo-a.jpg');
    await photoFile.writeAsBytes(<int>[1]);

    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: jsonEncode(<String, Object>{
        'schemaVersion': TripStore.schemaVersion,
        'trips': <Object>[
          <String, Object>{
            'id': 'trip-1',
            'title': 'テスト旅行',
            'photos': <Object>[photoFile.path],
          },
        ],
        'unassignedPhotos': <Object>[],
        'prefectureStates': <String, Object>{},
      }),
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          if (call.method == 'getSharedUris') {
            return <String, dynamic>{'successes': <Map<String, dynamic>>[]};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PendingDeletionStore storeWith({Duration? undoWindow}) {
    return PendingDeletionStore(
      now: () => DateTime.utc(2026, 1, 1),
      undoWindow: undoWindow ?? const Duration(seconds: 30),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    PendingDeletionStore? store,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(pendingDeletionStore: store ?? storeWith())),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 旅行タブへ移動し、メニューから「写真も削除」を確定する。
  ///
  /// メニューと確定ダイアログの操作および実ファイルIOはtester.runAsyncの中で
  /// 実行する（probeで検証済みの手順）。
  Future<void> deleteTripViaMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.photo_album_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('テスト旅行'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('写真も削除').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('削除する'));
      // 実ファイルの退避と保存を完了させる。
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// SnackBarの「元に戻す」をタップし、復元の実IO完了を待つ。
  Future<void> tapUndo(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('元に戻す'));
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('削除するとSnackBarの元に戻すで旅行と写真を完全復元できる', (tester) async {
    await pumpApp(tester);

    await deleteTripViaMenu(tester);

    // 削除後: 一覧から消え、SnackBarとUndoアクションが表示される。
    expect(find.text('テスト旅行'), findsNothing);
    expect(find.text('旅行を削除しました'), findsOneWidget);
    expect(find.text('元に戻す'), findsOneWidget);
    // 写真は退避されている。
    expect(photoFile.existsSync(), isFalse);
    expect(
      File(
        '${tempDir.path}/pending-deletions/trip-1/0-photo-a.jpg',
      ).existsSync(),
      isTrue,
    );

    await tapUndo(tester);

    // Undo後: 旅行・写真ファイル・退避領域の後始末が完了している。
    expect(find.text('旅行と写真を元に戻しました'), findsOneWidget);
    expect(find.text('テスト旅行'), findsOneWidget);
    expect(photoFile.existsSync(), isTrue);
    expect(
      Directory('${tempDir.path}/pending-deletions/trip-1').existsSync(),
      isFalse,
    );

    // 残るSnackBar（実時間タイマー）を実時間で消化してから終了する。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('期限が過ぎると退避写真が物理削除される', (tester) async {
    // undoWindowを短くし、実時間タイマー（runAsync内で作成される）が
    // テスト中に発火して確定削除まで進むことを確認する。
    await pumpApp(
      tester,
      store: storeWith(undoWindow: const Duration(seconds: 1)),
    );

    await deleteTripViaMenu(tester);
    expect(find.text('元に戻す'), findsOneWidget);

    // 実時間で1秒を超えて待ち、期限タイマーと確定削除のIOを完了させる。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2500)),
    );

    expect(find.text('テスト旅行'), findsNothing);
    expect(photoFile.existsSync(), isFalse);
    expect(
      Directory('${tempDir.path}/pending-deletions/trip-1').existsSync(),
      isFalse,
    );

    // 期限切れ後はUndoしても何も復元されない（確定削除済みのため）。
    await tapUndo(tester);
    expect(find.text('テスト旅行'), findsNothing);
    expect(photoFile.existsSync(), isFalse);
    expect(
      Directory('${tempDir.path}/pending-deletions/trip-1').existsSync(),
      isFalse,
    );

    // 残るSnackBar（実時間タイマー）を実時間で消化してから終了する。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('元に戻す'), findsNothing);
  });

  testWidgets('削除を再起動相当（recover）で回収しUndoできる', (tester) async {
    await pumpApp(tester);

    await deleteTripViaMenu(tester);
    expect(find.text('元に戻す'), findsOneWidget);

    // 新しいストア（=再起動）でmanifestを検査するとactiveとして復元される。
    final recovery = await tester.runAsync(
      () => storeWith().recover(tempDir, tripExists: (_) => false),
    );
    expect(recovery!.active.length, 1);

    // 回収したpendingを実際に復元する。
    final pending = recovery.active.single;
    final restored = await tester.runAsync(() => storeWith().restore(pending));
    expect(restored!.photos.length, 1);
    expect(photoFile.existsSync(), isTrue);

    // 進行中のUIタイマーを消化して終了する。
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
  });
}
