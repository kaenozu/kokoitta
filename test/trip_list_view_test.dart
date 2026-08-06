import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';
import 'package:kokoitta_app/photo.dart';

void main() {
  test('captured date and location summaries use available metadata only', () {
    final photos = <Photo>[
      Photo(
        id: '2',
        file: File('second.jpg'),
        capturedAt: DateTime(2026, 5, 3),
        location: '京都府',
      ),
      Photo(
        id: '1',
        file: File('first.jpg'),
        capturedAt: DateTime(2026, 5, 1),
        location: '東京都',
      ),
      Photo(
        id: '3',
        file: File('third.jpg'),
        location: '京都府',
      ),
      Photo(
        id: '4',
        file: File('fourth.jpg'),
        location: '長野県',
      ),
    ];

    expect(formatTripCapturedAt(photos), '2026年5月1日〜2026年5月3日');
    expect(formatTripLocations(photos), '京都府・東京都 ほか1件');
    expect(formatTripCapturedAt(const <Photo>[]), isNull);
    expect(formatTripLocations(const <Photo>[]), isNull);
  });

  testWidgets('empty state remains usable at 360px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: KokoittaTripListView(
            items: const <TripListItem>[],
            onAddPhotos: () {},
            onRestoreBackup: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最初の旅の思い出をつくりましょう'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '写真を追加'), findsOneWidget);
    expect(find.text('バックアップから復元'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards expose and execute one semantic navigation action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    const label =
        'とても長い旅行タイトルでも折り返して表示される旅行、24枚の写真、'
        '2026年4月1日〜2026年4月5日、埼玉県・東京都。詳細を開く';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.dark),
        home: KokoittaTripListView(
          items: <TripListItem>[
            TripListItem(
              title: 'とても長い旅行タイトルでも折り返して表示される旅行',
              photoCount: 24,
              capturedAtLabel: '2026年4月1日〜2026年4月5日',
              locationLabel: '埼玉県・東京都',
              image: const KokoittaPhotoPlaceholder(
                state: KokoittaPhotoPlaceholderState.missing,
                aspect: KokoittaImageAspect.wide,
              ),
              onTap: () => taps += 1,
            ),
          ],
          onAddPhotos: () {},
          onRestoreBackup: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.bySemanticsLabel(label);
    expect(card, findsOneWidget);
    expect(
      tester.getSemantics(card),
      matchesSemantics(
        label: label,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(card);
    expect(taps, 1);
    expect(find.text('24枚の思い出'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('tablet width arranges cards in two columns', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    TripListItem item(String title) => TripListItem(
          title: title,
          photoCount: 1,
          image: const KokoittaPhotoPlaceholder(
            state: KokoittaPhotoPlaceholderState.empty,
            aspect: KokoittaImageAspect.wide,
          ),
          onTap: () {},
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: KokoittaTripListView(
          items: <TripListItem>[item('旅行A'), item('旅行B')],
          onAddPhotos: () {},
          onRestoreBackup: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final first = tester.getTopLeft(find.text('旅行A'));
    final second = tester.getTopLeft(find.text('旅行B'));
    expect((first.dy - second.dy).abs(), lessThan(40));
    expect(second.dx, greaterThan(first.dx));
    expect(tester.takeException(), isNull);
  });
}
