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
    final photos = [
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

  testWidgets('double-tap callback toggles zoom and reset', (tester) async {
    final photo = Photo.fromFile(File('/virtual/photo.jpg'), id: 'photo');
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [photo],
          initialIndex: 0,
          imageBuilder: _memoryFreeImage,
        ),
      ),
    );
    await tester.pump();

    final target = find.byKey(const ValueKey('photo-viewer-0'));
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
  });

  testWidgets('missing file shows a recoverable fallback', (tester) async {
    final photo = Photo.fromFile(
      File('/definitely/missing/photo.jpg'),
      id: 'missing',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [photo],
          initialIndex: 0,
          imageBuilder: (_, _, _, _) => const PhotoLoadFallback(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('写真を表示できません'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
