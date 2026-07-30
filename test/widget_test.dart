import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/main.dart';
import 'package:kokoitta_app/operation_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kaenozu.kokoitta/share');

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
    final prefectureChip = find.ancestor(
      of: find.text('北海道'),
      matching: find.byType(ActionChip),
    );
    expect(tester.widget<ActionChip>(prefectureChip).onPressed, isNull);

    hold.complete();
    await mutation;
    await tester.pump();

    expect(tester.widget<IconButton>(addPhotoButton).onPressed, isNotNull);
  });
}
