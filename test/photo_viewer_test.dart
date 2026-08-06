import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/photo_viewer.dart';

Widget _memoryFreeImage(
  BuildContext context,
  File file,
  int cacheWidth,
  String semanticLabel,
) => const SizedBox.expand();

void main() {
  testWidgets('empty viewer stays navigable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PhotoViewer(photos: [], initialIndex: 0)),
    );
    expect(find.text('写真がありません'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('opens requested page and follows PageView navigation', (
    tester,
  ) async {
    final photos = <Photo>[
      Photo.fromFile(File('/virtual/first.jpg'), id: 'first'),
      Photo.fromFile(File('/virtual/second.jpg'), id: 'second'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: photos,
          initialIndex: 1,
          imageBuilder: _memoryFreeImage,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('写真 2 / 2'), findsOneWidget);

    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(0);
    await tester.pump();
    expect(find.text('写真 1 / 2'), findsOneWidget);
  });

  testWidgets('previous and next controls are explicit alternatives to swipe', (
    tester,
  ) async {
    final photos = <Photo>[
      Photo.fromFile(File('/virtual/first.jpg'), id: 'first'),
      Photo.fromFile(File('/virtual/second.jpg'), id: 'second'),
      Photo.fromFile(File('/virtual/third.jpg'), id: 'third'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: photos,
          initialIndex: 0,
          imageBuilder: _memoryFreeImage,
        ),
      ),
    );
    await tester.pump();

    IconButton button(IconData icon) => tester.widget<IconButton>(
      find
          .ancestor(of: find.byIcon(icon), matching: find.byType(IconButton))
          .first,
    );
    final previous = button(Icons.chevron_left);
    expect(previous.onPressed, isNull);
    expect(button(Icons.chevron_right).onPressed, isNotNull);

    await tester.tap(find.byTooltip('次の写真'));
    await tester.pumpAndSettle();
    expect(find.text('写真 2 / 3'), findsOneWidget);
    expect(button(Icons.chevron_left).onPressed, isNotNull);
  });

  testWidgets('share and delete receive only the current photo', (
    tester,
  ) async {
    final first = Photo.fromFile(File('/virtual/first.jpg'), id: 'first');
    final second = Photo.fromFile(File('/virtual/second.jpg'), id: 'second');
    Photo? shared;
    Photo? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          title: '旅行A',
          photos: <Photo>[first, second],
          initialIndex: 1,
          imageBuilder: _memoryFreeImage,
          onShare: (photo) => shared = photo,
          onDelete: (photo) => deleted = photo,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('現在の写真を共有'));
    await tester.tap(find.byTooltip('現在の写真を削除'));
    expect(shared?.id, 'second');
    expect(deleted?.id, 'second');
    expect(find.bySemanticsLabel('写真 2 / 2'), findsOneWidget);
  });

  testWidgets('zoom is available to pointer and accessibility users', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final photo = Photo.fromFile(File('/virtual/photo.jpg'), id: 'photo');
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: <Photo>[photo],
          initialIndex: 0,
          imageBuilder: _memoryFreeImage,
        ),
      ),
    );
    await tester.pump();

    final semanticImage = find.bySemanticsLabel(
      '写真 1 / 1。ダブルタップで拡大または元に戻す',
    );
    expect(semanticImage, findsOneWidget);
    expect(
      tester.getSemantics(semanticImage),
      matchesSemantics(
        label: '写真 1 / 1。ダブルタップで拡大または元に戻す',
        isImage: true,
        hasTapAction: true,
      ),
    );

    final target = find.byKey(const ValueKey<String>('photo-viewer-0'));
    InteractiveViewer current() => tester.widget<InteractiveViewer>(target);
    GestureDetector gesture() => tester.widget<GestureDetector>(
      find.ancestor(of: target, matching: find.byType(GestureDetector)).first,
    );

    expect(current().transformationController!.value.getMaxScaleOnAxis(), 1);
    gesture().onDoubleTap!();
    await tester.pump();
    expect(
      current().transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(2),
    );
    gesture().onDoubleTap!();
    await tester.pump();
    expect(current().transformationController!.value.getMaxScaleOnAxis(), 1);
    semantics.dispose();
  });

  testWidgets('missing file shows a recoverable fallback', (tester) async {
    final photo = Photo.fromFile(
      File('/definitely/missing/photo.jpg'),
      id: 'missing',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: <Photo>[photo],
          initialIndex: 0,
          imageBuilder: (_, _, _, _) => const PhotoLoadFallback(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('写真を表示できません'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel('写真を表示できません。戻る操作は利用できます'),
      findsOneWidget,
    );
  });
}
