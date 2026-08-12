import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/offline_japan_map.dart';

void main() {
  testWidgets('47都道府県を安定したコードで表示する', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: OfflineJapanMap(states: <String, String>{}),
            ),
          ),
        ),
      ),
    );

    for (var code = 1; code <= OfflineJapanMap.prefectureCount; code++) {
      expect(
        find.byKey(
          ValueKey<String>('prefecture-map-${code.toString().padLeft(2, '0')}'),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('北海道・東京・沖縄のタップと状態を意味的に区別する', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: OfflineJapanMap(
                states: const <String, String>{
                  '北海道': 'visited',
                  '東京都': 'transit',
                  '沖縄県': 'unvisited',
                },
                onPrefectureTap: tapped.add,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('北海道、訪問済み')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('東京都、通過')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('沖縄県、未訪問')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('北海道、訪問済み。タップすると状態を選択')),
      findsOneWidget,
    );

    for (final entry in const <String, String>{
      '01': '北海道',
      '13': '東京都',
      '47': '沖縄県',
    }.entries) {
      final finder = find.byKey(
        ValueKey<String>('prefecture-map-${entry.key}'),
      );
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }

    expect(tapped, <String>['北海道', '東京都', '沖縄県']);
  });

  testWidgets('小型Android相当幅とダークテーマで見切れず描画する', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: OfflineJapanMap(states: <String, String>{}),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('prefecture-map-01')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('prefecture-map-47')),
      findsOneWidget,
    );
  });
}
