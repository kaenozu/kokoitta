import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/image_decode.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/operation_coordinator.dart';
import 'package:kokoitta_app/trip_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 最小の有効な1x1 PNG。
final List<int> _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

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
    await tester.pumpWidget(const KokoittaApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ここいった'), findsOneWidget);
    expect(find.text('地図'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('写真を追加'), findsOneWidget);
  });

  testWidgets('busy中はデータ変更操作とバックアップメニューを無効化する', (tester) async {
    final coordinator = OperationCoordinator();
    await tester.pumpWidget(
      MaterialApp(home: HomePage(operationCoordinator: coordinator)),
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
    expect(find.text('都道府県マップ'), findsOneWidget);

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
  });

  testWidgets('一覧カードのサムネイルは表示寸法とDPRからデコード幅が決まる', (tester) async {
    seedAppData(<Map<String, Object>>[
      tripRecord('trip-1', <File>[photoFiles[0], photoFiles[1]]),
    ]);
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const KokoittaApp());
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

    await tester.pumpWidget(const KokoittaApp());
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

    await tester.pumpWidget(const KokoittaApp());
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

    await tester.pumpWidget(const KokoittaApp());
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
    // 開始前に一時停止し、スタートアップのStorageCleanupが photos/ 配下を
    // 走査し終えるのを待つ。取り込み中のコピー先をorphanと誤判定して
    // 削除する競合（コピー失敗 → 取り込み不成立）を避けるため。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSharedUris') {
            await Future<void>.delayed(const Duration(seconds: 3));
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
}
