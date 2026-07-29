import 'package:flutter_test/flutter_test.dart';

import 'package:kokoitta_app/main.dart';

void main() {
  testWidgets('ホームに地図と旅行タブを表示する', (tester) async {
    await tester.pumpWidget(const KokoittaApp());
    expect(find.text('ここいった'), findsOneWidget);
    expect(find.text('地図'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('写真を追加'), findsOneWidget);
  });
}

