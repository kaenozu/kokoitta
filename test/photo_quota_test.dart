import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/photo_quota.dart';

void main() {
  for (final entry in <int, (int, bool, bool)>{
    0: (300, false, false),
    299: (1, false, false),
    300: (0, true, false),
    301: (0, true, true),
  }.entries) {
    test('quota ${entry.key} has safe boundaries', () {
      final status = PhotoQuotaStatus(count: entry.key);
      expect(status.remaining, entry.value.$1);
      expect(status.reached, entry.value.$2);
      expect(status.exceeded, entry.value.$3);
    });
  }

  testWidgets('quota card exposes count, remaining and add availability', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PhotoQuotaCard(status: PhotoQuotaStatus(count: 299)),
        ),
      ),
    );
    expect(find.text('写真 299 / 300枚'), findsOneWidget);
    expect(find.text('残り 1枚'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(PhotoQuotaCard)),
      matchesSemantics(
        label: '写真使用数 299枚、上限 300枚、残り1枚、写真追加可能',
        isLiveRegion: true,
      ),
    );
    semantics.dispose();
  });
}
