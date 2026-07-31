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
        'unassignedPhotos': <String>[],
        'prefectureStates': <String, String>{},
      }),
    });
  }

  Map<String, Object> tripRecord(String id, Iterable<File> photos) =>
      <String, Object>{
        'id': id,
        'title': 'テスト旅行 $id',
        'photos': photos.map((file) => file.path).toList(growable: false),
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
    expect(
      find.byKey(const ValueKey<String>('prefecture-map-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('prefecture-map-47')),
      findsOneWidget,
    );
  });

  testWidgets('地図タップで状態を保存し再起動後も維持する', (tester) async {
    const hokkaidoKey = ValueKey<String>('prefecture-map-01');

    await tester.pumpWidget(const KokoittaApp());
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

    expect(
      find.bySemanticsLabel(RegExp('北海道、訪問済み')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(const KokoittaApp());
    await tester.pumpAndSettle();

    final restoredHokkaido = find.byKey(hokkaidoKey);
    await tester.ensureVisible(restoredHokkaido);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('北海道、訪問済み')),
      findsOneWidget,
    );
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
}
