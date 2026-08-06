import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';

void main() {
  testWidgets('prefecture list tile exposes and executes one tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: Scaffold(
          body: PrefectureStateListTile(
            name: '東京都',
            currentLabel: '未訪問',
            nextLabel: '訪問済み',
            icon: Icons.circle_outlined,
            onTap: () => taps += 1,
          ),
        ),
      ),
    );

    final tile = find.bySemanticsLabel('東京都、未訪問。タップすると訪問済みに変更');
    expect(tile, findsOneWidget);
    expect(
      tester.getSemantics(tile),
      matchesSemantics(
        label: '東京都、未訪問。タップすると訪問済みに変更',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(tile);
    expect(taps, 1);
    semantics.dispose();
  });
}
