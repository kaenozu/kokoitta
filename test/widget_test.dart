import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/image_decode.dart';
import 'package:kokoitta_app/import_progress.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/operation_coordinator.dart';
import 'package:kokoitta_app/pending_deletion.dart';
import 'package:kokoitta_app/storage_cleanup.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 最小の有効な1x1 PNG。
final List<int> _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// 起動時cleanupの代わりに即完了するfake runner。
///
/// cleanup本体の検証はcleanup_serialization_test.dartと共有取り込みテストが
/// 担う。ここでは実ファイルI/O（fake-async環境で完了しない
/// [StorageCleanup.run]）による `pumpAndSettle` のハングを避けるため、
/// 注入する。
Future<void> _noopCleanup(AppData data) async {}

/// 共有取り込みの保存完了を期限付きでポーリングする。
///
/// [documentsDir] 直下へコピーされた写真のレコードが、保存JSON内の旅行に
/// 含まれるまで待つ。書き込み途中の一時的な失敗（空文字列、デコード失敗、
/// レコード未反映）は期限まで再試行し、最後に発生した例外をタイムアウト時の
/// 失敗メッセージに含める。
Future<Map<String, dynamic>?> _waitForImportedPhotoJson(
  String documentsDir, {
  required Duration timeout,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final deadline = DateTime.now().add(timeout);
  const interval = Duration(milliseconds: 50);
  Object? lastError;
  String? lastRaw;
  Map<String, dynamic>? lastDecoded;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastRaw = preferences.getString(TripStore.dataKey);
      if (lastRaw == null || lastRaw.isEmpty) {
        lastError = StateError('保存データがまだ書き込まれていません');
      } else {
        lastDecoded = jsonDecode(lastRaw) as Map<String, dynamic>;
        final photo = _findCopiedPhoto(lastDecoded, documentsDir);
        if (photo != null) return lastDecoded;
        lastError = StateError('取り込まれた写真レコードが見つかりません');
      }
    } on FormatException catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(interval);
  }
  fail(
    '共有取り込みの保存完了をタイムアウトしました。'
    '上限: $timeout。確認対象JSON: ${TripStore.dataKey}。'
    '最終エラー: $lastError。最終JSON: $lastRaw',
  );
}

/// 保存JSONから [documentsDir] 直下へコピーされた写真レコードを探す。
Map<String, dynamic>? _findCopiedPhoto(
  Map<String, dynamic> decoded,
  String documentsDir,
) {
  final trips = decoded['trips'];
  if (trips is! List) return null;
  for (final trip in trips) {
    if (trip is! Map) continue;
    final photos = trip['photos'];
    if (photos is! List) continue;
    for (final photo in photos) {
      if (photo is! Map) continue;
      final path = photo['path'];
      if (path is String && path.startsWith(documentsDir)) {
        return Map<String, dynamic>.from(photo);
      }
    }
  }
  return null;
}

/// 保存JSONに含まれる旅行数が [expected] 件になるまで期限付きでポーリングする。
///
/// 書き込み途中の一時的な失敗（空文字列、デコード失敗）は期限まで再試行し、
/// タイムアウト時は最後のJSONとエラーを失敗メッセージに含める。
Future<Map<String, dynamic>?> _waitForTripCount(
  int expected, {
  required Duration timeout,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  String? lastRaw;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastRaw = preferences.getString(TripStore.dataKey);
      if (lastRaw == null || lastRaw.isEmpty) {
        lastError = StateError('保存データがまだ書き込まれていません');
      } else {
        final decoded = jsonDecode(lastRaw) as Map<String, dynamic>;
        final trips = decoded['trips'];
        if (trips is List && trips.length == expected) return decoded;
        lastError = StateError('旅行数が$expected件ではありません');
      }
    } on FormatException catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(
    '保存JSONの旅行数が$expected件になるのをタイムアウトしました。'
    '上限: $timeout。最終エラー: $lastError。最終JSON: $lastRaw',
  );
}

/// 保存(commit)の最初の書き込みが始まるのを期限付きでポーリングする。
///
/// [Future.timeout] はfake async / runAsync間のzone境界で再開が信用できない
/// ため、completerの状態を実時間ポーリングで確認する。
Future<void> _waitForImportSaveStarted(
  _HoldingPrefsStore store, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (store.importSaveStarted.isCompleted) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('保存(commit)の書き込みが始まるのをタイムアウトしました。上限: $timeout');
}

/// [store] のdataKey書き込みが [expected] 件になるのを期限付きでポーリングする。
///
/// gate解放後のアプリ側マイクロタスクは実時間待ちの間に処理される。
Future<void> _waitForDataKeyWrites(
  _HoldingPrefsStore store,
  int expected, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (store.dataKeyWrites.length >= expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail(
    'dataKey書き込みが$expected件になるのをタイムアウトしました。'
    '上限: $timeout。現在: ${store.dataKeyWrites.length}',
  );
}

/// 取り込み完了を表すimportResultイベントのペイロードを組み立てる。
Map<String, Object?> importResultEvent({
  required String requestId,
  required String path,
  String name = 'shared.jpg',
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
        'name': name,
        'mimeType': 'image/jpeg',
        'size': 1,
      },
    ],
    'failures': <Map<String, Object?>>[],
  };
}

/// 保存(commit)の書き込みを [release] が完了するまで保留するprefsストア。
///
/// commit保存の開始検知と、dataKeyへの書き込み順序の検証に使う。
class _HoldingPrefsStore extends InMemorySharedPreferencesStore {
  _HoldingPrefsStore() : super.empty();

  /// 非nullの間、全てのsetValueをこのFutureの完了までブロックする。
  Completer<void>? release;

  /// [release] をセットした後の最初のsetValueで完了する。
  final Completer<void> importSaveStarted = Completer<void>();

  /// `flutter.` 付きdataKeyへ実際に書き込まれた値の履歴。
  final List<String> dataKeyWrites = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final gate = release;
    if (gate != null && !importSaveStarted.isCompleted) {
      importSaveStarted.complete();
    }
    if (gate != null) await gate.future;
    // gate稼働中（=コミット保存の保留期間）のdataKey書き込みだけを記録する。
    // 起動時のcanonical保存は検証対象外。
    if (gate != null && key == 'flutter.${TripStore.dataKey}') {
      dataKeyWrites.add(value as String);
    }
    return super.setValue(valueType, key, value);
  }
}

/// 全ての読み書きが失敗するprefsストア。ロード失敗時の挙動検証用。
class _ThrowingPrefsStore extends InMemorySharedPreferencesStore {
  _ThrowingPrefsStore() : super.empty();

  int writeCount = 0;

  @override
  Future<Map<String, Object>> getAll() {
    throw StateError('読み込み失敗のテスト用');
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    writeCount += 1;
    throw StateError('書き込み失敗のテスト用');
  }
}

/// 初期ロードは許可し、取り込みcommitだけを失敗させるprefsストア。
class _CommitFailingPrefsStore extends InMemorySharedPreferencesStore {
  _CommitFailingPrefsStore() : super.empty();

  bool failWrites = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failWrites) {
      throw StateError('commit失敗のテスト用');
    }
    return super.setValue(valueType, key, value);
  }
}

/// path_providerのモックを登録し、テスト終了時に解除する。
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

/// テスト用の一時documentsディレクトリを作成し、後始末を登録する。
Future<Directory> createDocumentsDir(WidgetTester tester) async {
  final documentsDir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('kokoitta-doc-dir'),
  ))!;
  addTearDown(() async {
    await tester.runAsync(() async {
      try {
        await documentsDir.delete(recursive: true);
      } on FileSystemException {
        // ベストエフォートで後始末する。
      }
    });
  });
  return documentsDir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kaenozu.kokoitta/share');

  // FakeAsync環境ではIsolate.runが完了せずload()が停止するため、
  // 存在判定のisolateオフロードをテストでは無効化する。
  TripStore.resolveExistenceInIsolate = false;

  late Directory photoDirectory;
  late List<File> photoFiles;

  setUpAll(() async {
    photoDirectory = await Directory.systemTemp.createTemp(
      'kokoitta-widget-photos',
    );
    photoFiles = <File>[];
    for (var i = 0; i < 300; i++) {
      final file = File('${photoDirectory.path}/photo_$i.jpg');
      await file.writeAsBytes(_pngBytes);
      photoFiles.add(file);
    }
  });

  tearDownAll(() async {
    try {
      await photoDirectory.delete(recursive: true);
    } on FileSystemException {
      // Windows上で画像ハンドルが残存することがあるため、ベストエフォートで後始末する。
    }
  });

  void seedAppData(
    List<Map<String, Object>> trips, {
    Map<String, String> prefectureStates = const <String, String>{},
  }) {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: jsonEncode(<String, Object>{
        'schemaVersion': TripStore.schemaVersion,
        'trips': trips,
        'unassignedPhotos': <Object>[],
        'prefectureStates': prefectureStates,
      }),
    });
  }

  Map<String, Object> tripRecord(String id, Iterable<File> photos) =>
      <String, Object>{
        'id': id,
        'title': 'テスト旅行 $id',
        'photos': photos
            .map(
              (file) => <String, Object>{
                'id': TripStore.legacyPhotoId(file.path),
                'path': file.path,
              },
            )
            .toList(growable: false),
      };

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSharedUris') {
            return <String, dynamic>{'successes': <Map<String, dynamic>>[]};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// 共有イベントをアプリ側ハンドラへ配信する。
  ///
  /// [waitForReply] がtrueのときはハンドラの完了（=終端イベントの取り込み
  /// 完了）まで待つ。保存が保留されるキャンセル検証ではfalseにして配信のみ
  /// 行い、進行中の取り込みを妨げない。
  Future<void> sendImportEvent(
    WidgetTester tester, {
    required String method,
    required Map<String, Object?> arguments,
    bool waitForReply = true,
  }) async {
    final reply = TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
          null,
        );
    if (waitForReply) await reply;
    await tester.pump();
  }

  /// 起動時のロード（と初期保存）が終わり、FABが表示されるまで待つ。
  ///
  /// 実I/Oの完了を待つrunAsync中で使う。load中にprefsをブロックすると
  /// deadlockするため、gateをかける前に必ず待つ。
  Future<void> waitUntilLoaded(WidgetTester tester) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) &&
        tester.widgetList(find.text('写真を追加')).isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
    expect(find.text('写真を追加'), findsOneWidget);
  }

  /// [text] が画面に現れるまでポーリングする。実I/Oを伴う操作の完了待ち。
  ///
  /// SnackBarの入退場アニメーションを進めるため、fake clockも進める
  /// （pump()だけでは進まず、待機中のSnackBarが表示されないことがある）。
  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline) &&
        tester.widgetList(find.text(text)).isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(text), findsOneWidget);
  }

  /// 旅行タブの削除メニューから「写真も削除」を確定するまで操作する。
  ///
  /// 削除mutationは実ファイルI/OのためrunAsyncの中で呼ぶこと。メニュー・
  /// ダイアログの開閉アニメーションはpumpAndSettleで完了させてからタップする。
  Future<void> deleteTripViaMenu(WidgetTester tester) async {
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写真も削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除する'));
    await tester.pump();
  }

  /// 共有元の一時ファイルを写真用ディレクトリに作る。
  Future<File> createSourceFile(WidgetTester tester, String name) async {
    final file = File('${photoDirectory.path}/$name');
    await tester.runAsync(() => file.writeAsBytes(_pngBytes));
    return file;
  }

  testWidgets('ホームに地図と旅行タブを表示する', (tester) async {
    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ここいった'), findsOneWidget);
    expect(find.text('地図'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('写真を追加'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('prefecture-map-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('prefecture-map-47')),
      findsOneWidget,
    );
  });

  testWidgets('共有importのprogressを表示し古いrequestのeventを無視する', (tester) async {
    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pump(const Duration(milliseconds: 100));

    Future<void> sendNativeEvent(
      String method,
      Map<String, Object?> args,
    ) async {
      final done = Completer<ByteData?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            done.complete,
          );
      await done.future;
      await tester.pump();
    }

    await sendNativeEvent('importProgress', <String, Object?>{
      'requestId': 'request-b',
      'phase': 'copying',
      'processed': 1,
      'total': 2,
      'succeeded': 1,
      'failed': 0,
      'terminal': false,
    });
    expect(find.text('取り込み 1 / 2'), findsOneWidget);

    await sendNativeEvent('importProgress', <String, Object?>{
      'requestId': 'request-a',
      'phase': 'copying',
      'processed': 2,
      'total': 2,
      'succeeded': 2,
      'failed': 0,
      'terminal': false,
    });
    expect(find.text('取り込み 1 / 2'), findsOneWidget);
  });

  testWidgets('地図タップで状態を保存し再起動後も維持する', (tester) async {
    const hokkaidoKey = ValueKey<String>('prefecture-map-01');

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();

    final hokkaido = find.byKey(hokkaidoKey);
    final hokkaidoTapTarget = find.descendant(
      of: hokkaido,
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(hokkaidoTapTarget);
    await tester.pumpAndSettle();
    await tester.tap(hokkaidoTapTarget);
    await tester.pumpAndSettle();

    // ピッカー（BottomSheet）が開き、訪問済みを明示選択する
    expect(find.text('北海道の状態を選択'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '訪問済み'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('北海道、訪問済み')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();

    final restoredHokkaido = find.byKey(hokkaidoKey);
    await tester.ensureVisible(restoredHokkaido);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('北海道、訪問済み')), findsOneWidget);
  });

  testWidgets('保存キーの都道府県状態が地図の着色とピッカーに実結線で反映される', (tester) async {
    seedAppData(
      <Map<String, Object>>[],
      prefectureStates: const <String, String>{
        '東京': 'visited',
        '大阪': 'transit',
      },
    );

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();

    // 無接尾辞の保存キーが接尾辞付きラベルのタイルへ着色される。
    expect(find.bySemanticsLabel(RegExp('東京都、訪問済み')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('大阪府、通過')), findsOneWidget);

    // タップ経路も保存キーで結線され、ピッカーの現在状態が正しい。
    final tokyoTapTarget = find.descendant(
      of: find.byKey(const ValueKey<String>('prefecture-map-13')),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(tokyoTapTarget);
    await tester.pumpAndSettle();
    await tester.tap(tokyoTapTarget);
    await tester.pumpAndSettle();

    expect(find.text('東京の状態を選択'), findsOneWidget);
    expect(find.text('現在: 訪問済み'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '未訪問'));
    await tester.pumpAndSettle();

    // 保存は無接尾辞キーで行われ、既存の大阪状態は壊さない。
    expect(find.bySemanticsLabel(RegExp('東京都、未訪問')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('大阪府、通過')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();

    final restoredTokyo = find.descendant(
      of: find.byKey(const ValueKey<String>('prefecture-map-13')),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(restoredTokyo);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('東京都、未訪問')), findsOneWidget);
    final restoredOsaka = find.descendant(
      of: find.byKey(const ValueKey<String>('prefecture-map-27')),
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(restoredOsaka);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('大阪府、通過')), findsOneWidget);
  });

  testWidgets('busy中はデータ変更操作とバックアップメニューを無効化する', (tester) async {
    final coordinator = OperationCoordinator();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          operationCoordinator: coordinator,
          cleanupRunner: _noopCleanup,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));

    final hold = Completer<void>();
    final mutation = coordinator.runMutation(() => hold.future);
    expect(coordinator.isBusy, isTrue);
    await tester.pump(const Duration(milliseconds: 100));

    final addPhotoButton = find.widgetWithText(FilledButton, '写真を追加');
    expect(tester.widget<FilledButton>(addPhotoButton).onPressed, isNull);

    final hokkaidoTapTarget = find.descendant(
      of: find.byKey(const ValueKey<String>('prefecture-map-01')),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(hokkaidoTapTarget).onTap, isNull);

    hold.complete();
    await mutation;
    await tester.pump();

    final reenabledAddPhotoButton = find.widgetWithText(FilledButton, '写真を追加');
    expect(
      tester.widget<FilledButton>(reenabledAddPhotoButton).onPressed,
      isNotNull,
    );
    expect(tester.widget<InkWell>(hokkaidoTapTarget).onTap, isNotNull);
  });

  testWidgets('一覧カードのサムネイルは表示寸法とDPRからデコード幅が決まる', (tester) async {
    seedAppData(<Map<String, Object>>[
      tripRecord('trip-1', <File>[photoFiles[0], photoFiles[1]]),
    ]);
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    final size = tester.getSize(imageFinder);
    final image = tester.widget<Image>(imageFinder);
    final expected = thumbnailDecodeDimension(
      logicalWidth: size.width,
      logicalHeight: size.height,
      devicePixelRatio: tester.view.devicePixelRatio,
    );
    expect(image.image, isA<ResizeImage>());
    final resize = image.image as ResizeImage;
    expect(resize.width, expected);
    expect(resize.height, isNull);
    expect(expected, inInclusiveRange(64, 1600));
  });

  testWidgets('写真グリッドの各セルにもデコード幅が指定される', (tester) async {
    seedAppData(<Map<String, Object>>[
      tripRecord('trip-1', <File>[photoFiles[0], photoFiles[1], photoFiles[2]]),
    ]);

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('テスト旅行 trip-1'));
    await tester.pumpAndSettle();

    final gridImageFinder = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Image),
    );
    expect(gridImageFinder, findsWidgets);
    final size = tester.getSize(gridImageFinder.first);
    final image = tester.widget<Image>(gridImageFinder.first);
    final expected = thumbnailDecodeDimension(
      logicalWidth: size.width,
      logicalHeight: size.height,
      devicePixelRatio: tester.view.devicePixelRatio,
    );
    expect(image.image, isA<ResizeImage>());
    final resize = image.image as ResizeImage;
    expect(resize.width, expected);
    expect(resize.height, isNull);
  });

  testWidgets('画像読み込み失敗時はbroken-imageフォールバックが維持される', (tester) async {
    seedAppData(<Map<String, Object>>[
      tripRecord('trip-1', <File>[photoFiles[0]]),
    ]);

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    expect(image.errorBuilder, isNotNull);

    final fallback = image.errorBuilder!(
      tester.element(imageFinder),
      Exception('decode failed'),
      StackTrace.current,
    );
    await tester.pumpWidget(MaterialApp(home: fallback));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('300件の写真グリッドでも表示中Widgetのみ構築される', (tester) async {
    seedAppData(<Map<String, Object>>[tripRecord('trip-1', photoFiles)]);

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pumpAndSettle();
    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('テスト旅行 trip-1'));
    await tester.pumpAndSettle();

    final gridImageFinder = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Image),
    );
    final builtImages = tester.widgetList(gridImageFinder).length;
    expect(builtImages, greaterThan(0));
    expect(builtImages, lessThan(300));
  });

  testWidgets('共有からの取り込みでファイル更新日時が撮影日時に保存されない', (tester) async {
    late Directory documentsDir;
    late File source;
    await tester.runAsync(() async {
      source = File('${photoDirectory.path}/shared_source.jpg');
      await source.writeAsBytes(_pngBytes);
      final oldModified = DateTime(2000, 1, 1, 0, 0);
      await source.setLastModified(oldModified);
      documentsDir = await Directory.systemTemp.createTemp('kokoitta-doc-dir');
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        try {
          await documentsDir.delete(recursive: true);
        } on FileSystemException {
          // ベストエフォートで後始末する。
        }
      });
    });
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

    // 共有チャネルが取り込み対象ファイルを返すよう上書きする。
    // 起動時cleanupはOperationCoordinatorの同一キューで取り込みより先に
    // 実行されるため、固定delayでcleanup完了を待つ必要はない。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSharedUris') {
            return <String, dynamic>{
              'successes': <Map<String, dynamic>>[
                <String, dynamic>{'path': source.path},
              ],
              'overLimitCount': 0,
              'failures': <Map<String, dynamic>>[],
            };
          }
          return null;
        });

    Map<String, dynamic>? stored;
    await tester.runAsync(() async {
      // 実cleanupと共有取り込みが同一キューで直列化されることを確認するため、
      // fake runnerではなく実際のKokoittaAppを使用する。
      await tester.pumpWidget(const KokoittaApp());
      // 実I/O（ファイルコピー・削除・保存）の完了を実時間で待つ。
      // 保存完了はポーリングで検出し、タイミング非依存にする。
      stored = await _waitForImportedPhotoJson(
        documentsDir.path,
        timeout: const Duration(seconds: 20),
      );
    });
    await tester.pumpAndSettle();
    // 実I/Oの完了を待つ間にFlutter側へ例外が漏れていないこと。
    expect(tester.takeException(), isNull);
    final trips = stored!['trips'] as List;
    final storedPhoto =
        ((trips).single['photos'] as List).single as Map<String, dynamic>;
    // ソースファイルの更新日時（2000年）がcapturedAtとして永続化されてはならない。
    expect(storedPhoto.containsKey('capturedAt'), isFalse);
    expect(storedPhoto['id'], isA<String>());
    expect(storedPhoto['path'], isA<String>());
  });

  testWidgets('共有importは前方失敗と後方成功の対象対応を維持する', (tester) async {
    late Directory documentsDir;
    late File sourceB;
    ImportEvent? terminalEvent;

    await tester.runAsync(() async {
      sourceB = File('${photoDirectory.path}/source-B.jpg');
      await sourceB.writeAsBytes(_pngBytes);
      documentsDir = await Directory.systemTemp.createTemp(
        'kokoitta-doc-import-mapping',
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        try {
          await documentsDir.delete(recursive: true);
        } on FileSystemException {
          // ベストエフォートで後始末する。
        }
      });
    });

    _mockPathProvider(documentsDir);
    final missingSourceA = '${photoDirectory.path}/source-A-missing.jpg';
    await tester.runAsync(() async {
      expect(await File(missingSourceA).exists(), isFalse);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          onImportEvent: (event) {
            if (event.isTerminal) terminalEvent = event;
          },
        ),
      );
      await waitUntilLoaded(tester);
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: <String, Object?>{
          'requestId': 'request-forward-success',
          'phase': 'completed',
          'processed': 2,
          'total': 2,
          'succeeded': 2,
          'failed': 0,
          'terminal': true,
          'successes': <Map<String, Object?>>[
            <String, Object?>{
              'path': missingSourceA,
              'name': 'A.jpg',
              'mimeType': 'image/jpeg',
              'size': 1,
            },
            <String, Object?>{
              'path': sourceB.path,
              'name': 'B.jpg',
              'mimeType': 'image/jpeg',
              'size': 1,
            },
          ],
          'failures': <Map<String, Object?>>[],
        },
      );
    });

    await tester.runAsync(() async {
      final stored = await _waitForImportedPhotoJson(
        documentsDir.path,
        timeout: const Duration(seconds: 20),
      );
      final trips = stored!['trips'] as List;
      final storedPhotos = trips.single['photos'] as List;
      expect(storedPhotos, hasLength(1));
      expect(
        (storedPhotos.single as Map<String, dynamic>)['originalName'],
        'B.jpg',
      );
    });

    expect(terminalEvent, isNotNull);
    expect(terminalEvent!.phase, ImportPhase.partialFailure);
    expect(terminalEvent!.succeeded, 1);
    expect(terminalEvent!.successes, hasLength(1));
    expect(terminalEvent!.successes.single.path, sourceB.path);
    expect(terminalEvent!.successes.single.name, 'B.jpg');
    expect(terminalEvent!.failures, hasLength(1));
    expect(terminalEvent!.failures.single.index, 0);
    expect(terminalEvent!.failures.single.errorCode, 'copy_failed');
    expect(terminalEvent!.failed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('起動時cleanupと共有取り込みは同一キューで直列化され、新規写真が残る', (tester) async {
    late Directory documentsDir;
    late File source;
    final log = <String>[];

    await tester.runAsync(() async {
      source = File('${photoDirectory.path}/serialized_shared_source.jpg');
      await source.writeAsBytes(_pngBytes);
      documentsDir = await Directory.systemTemp.createTemp(
        'kokoitta-doc-serialized',
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        try {
          await documentsDir.delete(recursive: true);
        } on FileSystemException {
          // ベストエフォートで後始末する。
        }
      });
    });

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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSharedUris') {
            return <String, dynamic>{
              'successes': <Map<String, dynamic>>[
                <String, dynamic>{'path': source.path},
              ],
              'overLimitCount': 0,
              'failures': <Map<String, dynamic>>[],
            };
          }
          return null;
        });

    // cleanup本体の実I/O検証はcleanup_serialization_test.dartが担う。
    // ここではキュー直列化の順序を検証するため、cleanup runner自身が
    // 「実行時点の保存JSONに共有取り込みが含まれているか」を記録する。
    // 取り込みがcleanupより先行していれば tripsAtStart が0にならない。
    Future<void> cleanupRunner(AppData data) async {
      log.add('cleanup:start');
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(TripStore.dataKey);
      final decoded = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      log.add(
        'cleanup:tripsAtStart=${(decoded['trips'] as List? ?? []).length}',
      );
      log.add('cleanup:end');
    }

    Map<String, dynamic>? stored;
    late String storedPath;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: HomePage(cleanupRunner: cleanupRunner)),
      );
      stored = await _waitForImportedPhotoJson(
        documentsDir.path,
        timeout: const Duration(seconds: 20),
      );
      final trips = stored!['trips'] as List;
      final storedPhoto =
          ((trips).single['photos'] as List).single as Map<String, dynamic>;
      storedPath = storedPhoto['path'] as String;
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    // cleanupが共有取り込みより先に実行され、その時点では未保存だったこと。
    expect(log, <String>[
      'cleanup:start',
      'cleanup:tripsAtStart=0',
      'cleanup:end',
    ]);

    // cleanup完了後に取り込まれた新規写真が物理的に存在する。
    await tester.runAsync(() async {
      expect(await File(storedPath).exists(), isTrue);
    });
  });

  testWidgets('起動時cleanup中にWidgetを破棄してもUI APIを操作せず例外を出さない', (tester) async {
    final cleanupStarted = Completer<void>();
    final releaseCleanup = Completer<void>();
    final log = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          cleanupRunner: (_) async {
            log.add('cleanup:start');
            cleanupStarted.complete();
            await releaseCleanup.future;
            log.add('cleanup:end');
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await cleanupStarted.future.timeout(const Duration(seconds: 10));

    // cleanup実行中にWidgetを破棄する。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    releaseCleanup.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(log, <String>['cleanup:start', 'cleanup:end']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一URIセットをrequestIdを変えて2回共有すると両方取り込まれる', (tester) async {
    final source = await createSourceFile(tester, 'shared_reuse_source.jpg');
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(requestId: 'request-1', path: source.path),
      );
      // 1回目の取り込みが一時ファイルを削除するため、2回目は再作成する。
      await source.writeAsBytes(_pngBytes);
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(requestId: 'request-2', path: source.path),
      );
    });
    await tester.pump(const Duration(milliseconds: 100));

    // 同じURIセットでもrequestIdが新しければ2回目の共有も取り込まれる。
    final decoded = await tester.runAsync(
      () => _waitForTripCount(2, timeout: const Duration(seconds: 20)),
    );
    final trips = decoded!['trips'] as List<dynamic>;
    expect(trips.length, 2);
    expect((trips[0] as Map<dynamic, dynamic>)['title'], '共有からのおでかけ 1');
    expect((trips[1] as Map<dynamic, dynamic>)['title'], '共有からのおでかけ 2');
    final photos = <dynamic>[
      ...(trips[0] as Map<dynamic, dynamic>)['photos'] as List<dynamic>,
      ...(trips[1] as Map<dynamic, dynamic>)['photos'] as List<dynamic>,
    ];
    expect(photos.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取り込み中に別requestIdの共有イベントが届いても進行中の取り込みは失われない', (tester) async {
    final sourceA = await createSourceFile(tester, 'shared_busy_source_a.jpg');
    final sourceB = await createSourceFile(tester, 'shared_busy_source_b.jpg');
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);

    final store = _HoldingPrefsStore();
    SharedPreferencesStorePlatform.instance = store;

    await tester.runAsync(() async {
      await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
      await waitUntilLoaded(tester);

      store.release = Completer<void>();
      // 取り込みAが保存(commit)でブロックされている間に、別requestIdの
      // 終端イベントBを配信する。
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(
          requestId: 'request-a',
          path: sourceA.path,
        ),
        waitForReply: false,
      );
      await _waitForImportSaveStarted(
        store,
        timeout: const Duration(seconds: 10),
      );
      await tester.pump();
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(
          requestId: 'request-b',
          path: sourceB.path,
        ),
      );
      // Bはgateがbusyのため無視され、Aの進行表示が維持される。
      expect(find.text('取り込み 1 / 1'), findsOneWidget);

      store.release!.complete();
    });
    final decoded = await tester.runAsync(
      () => _waitForTripCount(1, timeout: const Duration(seconds: 20)),
    );
    final trips = decoded!['trips'] as List<dynamic>;
    expect(trips.length, 1);
    expect((trips[0] as Map<dynamic, dynamic>)['title'], '共有からのおでかけ 1');
    // Bの取り込みは実行されていない（一時ファイルも削除されていない）。
    await tester.runAsync(() async {
      expect(await sourceB.exists(), isTrue);
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存(commit)中のキャンセルはストアをpreviousDataへ巻き戻す', (tester) async {
    final source = await createSourceFile(tester, 'shared_cancel_source.jpg');
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);
    ImportEvent? terminalEvent;

    final store = _HoldingPrefsStore();
    SharedPreferencesStorePlatform.instance = store;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          onImportEvent: (event) {
            if (event.isTerminal) terminalEvent = event;
          },
        ),
      );
      await waitUntilLoaded(tester);

      store.release = Completer<void>();
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(requestId: 'request-c', path: source.path),
        waitForReply: false,
      );
      // commit保存がgateでブロックされている間にUIキャンセルする。
      await _waitForImportSaveStarted(
        store,
        timeout: const Duration(seconds: 10),
      );
      await tester.pump();
      expect(find.text('キャンセル'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      store.release!.complete();
    });
    // gate解放後のcommit→巻き戻しの書き込みは実時間待ちで完了を待つ。
    await tester.runAsync(
      () =>
          _waitForDataKeyWrites(store, 2, timeout: const Duration(seconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // commit→巻き戻しの順にdataKeyへ書き込まれていること。
    expect(store.dataKeyWrites.length, 2);
    int tripsCount(String raw) =>
        ((jsonDecode(raw) as Map<String, dynamic>)['trips'] as List).length;
    expect(tripsCount(store.dataKeyWrites[0]), 1);
    expect(tripsCount(store.dataKeyWrites[1]), 0);
    // 最終的な保存状態が0件に戻っていること。
    final preferences = await SharedPreferences.getInstance();
    final finalRaw = preferences.getString(TripStore.dataKey);
    expect(finalRaw, isNotNull);
    expect(tripsCount(finalRaw!), 0);
    // キャンセルした取り込みの成功SnackBarは出ないこと。
    expect(find.textContaining('取り込みました'), findsNothing);
    // コピーされた写真ファイルも削除されていること。
    await tester.runAsync(() async {
      final photosDir = Directory('${documentsDir.path}/photos');
      if (await photosDir.exists()) {
        expect(await photosDir.list().toList(), isEmpty);
      }
    });
    expect(terminalEvent, isNotNull);
    expect(terminalEvent!.phase, ImportPhase.cancelled);
    expect(terminalEvent!.succeeded, 0);
    expect(terminalEvent!.successes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('共有importのcommit失敗は保存状態と生成ファイルを残さない', (tester) async {
    final source = await createSourceFile(tester, 'shared_commit_failure.jpg');
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);
    final store = _CommitFailingPrefsStore();
    SharedPreferencesStorePlatform.instance = store;
    ImportEvent? terminalEvent;

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          onImportEvent: (event) {
            if (event.isTerminal) terminalEvent = event;
          },
        ),
      );
      await waitUntilLoaded(tester);
      store.failWrites = true;
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(
          requestId: 'request-commit-failure',
          path: source.path,
        ),
      );
    });

    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(TripStore.dataKey);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['trips'], isEmpty);
    expect(terminalEvent, isNotNull);
    expect(terminalEvent!.phase, ImportPhase.failed);
    expect(terminalEvent!.succeeded, 0);
    expect(terminalEvent!.successes, isEmpty);
    expect(terminalEvent!.failures.single.errorCode, 'save_failed');
    await tester.runAsync(() async {
      final photosDir = Directory('${documentsDir.path}/photos');
      if (await photosDir.exists()) {
        expect(await photosDir.list().toList(), isEmpty);
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存データのロードに失敗したら共有イベントを取り込まない', (tester) async {
    final source = await createSourceFile(
      tester,
      'shared_load_error_source.jpg',
    );
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);

    final store = _ThrowingPrefsStore();
    SharedPreferencesStorePlatform.instance = store;

    await tester.pumpWidget(KokoittaApp(cleanupRunner: _noopCleanup));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('保存データを読み込めませんでした'), findsOneWidget);

    await tester.runAsync(() async {
      await sendImportEvent(
        tester,
        method: 'importResult',
        arguments: importResultEvent(
          requestId: 'request-load-error',
          path: source.path,
        ),
      );
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // ロード失敗UIが維持され、取り込みも実行されていないこと。
    expect(find.text('保存データを読み込めませんでした'), findsOneWidget);
    expect(find.textContaining('取り込みました'), findsNothing);
    expect(store.writeCount, 0);
    await tester.runAsync(() async {
      expect(await source.exists(), isTrue);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('期限到達でUndo SnackBarは消え、完全削除メッセージは一度だけ表示される', (tester) async {
    seedAppData(<Map<String, Object>>[
      tripRecord('trip-1', <File>[photoFiles[0]]),
    ]);
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          pendingDeletionBuilder: () => PendingDeletionManager(
            store: SharedPreferencesPendingDeletionStore(),
            trashRoot: '${documentsDir.path}/pending-deletions',
            undoWindow: const Duration(seconds: 2),
          ),
        ),
      );
      await waitUntilLoaded(tester);
      await deleteTripViaMenu(tester);
      // 削除mutation（実ファイルI/O）と期限timer（実Timer）をrunAsync内で完結させる。
      await waitForText(tester, '旅行と写真を削除しました。30秒以内ならUndoできます');
    });

    // Undo SnackBarはUndo可能な窓と同じ期間だけ表示される。
    final undoSnackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(undoSnackBar.duration, const Duration(seconds: 2));

    // 期限到達を実時間で待つ。fake-asyncでは発火しない実Timerがここで発火する。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2600)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Undo SnackBarは消え、完全削除メッセージが一度だけ表示される。
    expect(find.text('旅行と写真を削除しました。30秒以内ならUndoできます'), findsNothing);
    expect(find.text('Undo期限が切れたため、写真を完全に削除しました'), findsOneWidget);
    expect(tester.widgetList(find.text('Undo期限が切れたため、写真を完全に削除しました')).length, 1);

    // 退避ファイルは物理削除され、manifestも掃除されている。
    await tester.runAsync(() async {
      final trashRoot = Directory('${documentsDir.path}/pending-deletions');
      if (await trashRoot.exists()) {
        final remaining = await trashRoot
            .list(recursive: true)
            .where((entity) => entity is File)
            .toList();
        expect(remaining, isEmpty);
      }
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('pendingDeletionManifestV1'), isNull);
    });
  });

  testWidgets('Undo操作でUndo SnackBarは即座に消え、期限切れメッセージは出ない', (tester) async {
    // 期限到達テストがphotoFiles[0]を物理削除するため、別ファイルを使う。
    seedAppData(<Map<String, Object>>[
      tripRecord('trip-1', <File>[photoFiles[1]]),
    ]);
    final documentsDir = await createDocumentsDir(tester);
    _mockPathProvider(documentsDir);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        KokoittaApp(
          cleanupRunner: _noopCleanup,
          pendingDeletionBuilder: () => PendingDeletionManager(
            store: SharedPreferencesPendingDeletionStore(),
            trashRoot: '${documentsDir.path}/pending-deletions',
            undoWindow: const Duration(seconds: 2),
          ),
        ),
      );
      await waitUntilLoaded(tester);
      await deleteTripViaMenu(tester);
      await waitForText(tester, '旅行と写真を削除しました。30秒以内ならUndoできます');
      // Undo SnackBarの表示アニメーションを完了させてからタップする。
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      await waitForText(tester, '旅行と写真を元に戻しました');
    });

    // Undo成功と同時にUndo SnackBarは消えている。
    expect(find.text('旅行と写真を削除しました。30秒以内ならUndoできます'), findsNothing);

    // 期限timerはUndoでキャンセルされるため、期限後も完全削除メッセージは出ない。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2600)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Undo期限が切れたため、写真を完全に削除しました'), findsNothing);
    expect(find.text('旅行と写真を元に戻しました'), findsOneWidget);

    // 写真は元の場所へ復元され、manifestも消えている。
    await tester.runAsync(() async {
      expect(await photoFiles[1].exists(), isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('pendingDeletionManifestV1'), isNull);
    });
  });
}
