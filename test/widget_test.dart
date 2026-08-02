import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/image_decode.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/models.dart';
import 'package:kokoitta_app/operation_coordinator.dart';
import 'package:kokoitta_app/storage_cleanup.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kaenozu.kokoitta/share');

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

  void seedAppData(List<Map<String, Object>> trips) {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TripStore.dataKey: jsonEncode(<String, Object>{
        'schemaVersion': TripStore.schemaVersion,
        'trips': trips,
        'unassignedPhotos': <Object>[],
        'prefectureStates': <String, String>{},
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

    final addPhotoButton = find.ancestor(
      of: find.byTooltip('写真を追加').first,
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(addPhotoButton).onPressed, isNull);

    final hokkaidoTapTarget = find.descendant(
      of: find.byKey(const ValueKey<String>('prefecture-map-01')),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(hokkaidoTapTarget).onTap, isNull);

    hold.complete();
    await mutation;
    await tester.pump();

    final reenabledAddPhotoButton = find.ancestor(
      of: find.byTooltip('写真を追加').first,
      matching: find.byType(IconButton),
    );
    expect(
      tester.widget<IconButton>(reenabledAddPhotoButton).onPressed,
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
}
