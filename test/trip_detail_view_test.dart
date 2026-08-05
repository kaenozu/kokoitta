import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/trip_detail_view.dart';

void main() {
  testWidgets('zero-photo detail keeps add and back actions available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: TripDetailView(
          title: '写真のない旅行',
          photos: const <Photo>[],
          onPhotoTap: (_) {},
          onAddPhotos: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('まだ写真がありません'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '写真を追加'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('grid tiles expose trip title position and total', (tester) async {
    final photos = List<Photo>.generate(
      4,
      (index) => Photo.fromFile(
        File('/virtual/photo-$index.jpg'),
        id: 'photo-$index',
      ),
    );
    int? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.dark),
        home: TripDetailView(
          title: '春の旅行',
          photos: photos,
          capturedAtLabel: '2026年4月1日〜2026年4月3日',
          locationLabel: '埼玉県・東京都',
          onPhotoTap: (index) => tapped = index,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('春の旅行の写真 1 / 4。拡大表示'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('春の旅行の写真 2 / 4。拡大表示'));
    expect(tapped, 1);
    expect(find.textContaining('4枚の写真'), findsOneWidget);
  });

  testWidgets('200 percent text uses a readable two-column grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photos = List<Photo>.generate(
      8,
      (index) => Photo.fromFile(File('/virtual/$index.jpg'), id: '$index'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: TripDetailView(
            title: '非常に長い旅行タイトルでも操作を失わない旅行の記録',
            photos: photos,
            onPhotoTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy state explains disabled add while management stays explicit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: TripDetailView(
          title: '旅行A',
          photos: const <Photo>[],
          onPhotoTap: (_) {},
          busyMessage: '削除処理を確認しています。',
          onAddPhotos: null,
          onShare: () {},
          onMoveToUnassigned: () {},
          onDelete: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('削除処理を確認しています。'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '写真を追加')).onPressed,
      isNull,
    );
    expect(find.byTooltip('旅行Aの管理メニュー'), findsOneWidget);
  });
}
