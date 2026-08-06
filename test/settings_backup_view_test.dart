import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';

void main() {
  Future<void> pumpView(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
    bool dark = false,
    bool busy = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        darkTheme: buildKokoittaTheme(Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsBackupView(
            isBusy: busy,
            canCreateBackup: true,
            canRestore: true,
            busyMessage: busy ? 'バックアップを作成しています。' : null,
            onCreateBackup: () {},
            onRestore: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('360 width and 200 percent text remain scrollable without overflow', (
    tester,
  ) async {
    await pumpView(
      tester,
      size: const Size(360, 800),
      textScale: 2,
    );
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('完全バックアップを作成'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark tablet layout keeps backup and restore actions', (tester) async {
    await pumpView(
      tester,
      size: const Size(800, 1200),
      dark: true,
    );
    expect(find.text('完全バックアップを作成'), findsOneWidget);
    expect(find.text('完全復元'), findsOneWidget);
    expect(find.text('注意が必要な操作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy state disables conflicting actions and explains why', (
    tester,
  ) async {
    await pumpView(
      tester,
      size: const Size(412, 915),
      busy: true,
    );
    expect(find.text('データを処理しています'), findsOneWidget);
    expect(find.text('バックアップを作成しています。'), findsOneWidget);
    final backupTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '完全バックアップを作成'),
    );
    final restoreTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '完全復元'),
    );
    expect(backupTile.enabled, isFalse);
    expect(restoreTile.enabled, isFalse);
  });

  testWidgets('backup and restore actions expose semantic tap actions', (
    tester,
  ) async {
    var backups = 0;
    var restores = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: Scaffold(
          body: SettingsBackupView(
            isBusy: false,
            canCreateBackup: true,
            canRestore: true,
            onCreateBackup: () => backups++,
            onRestore: () => restores++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('完全バックアップを作成'));
    await tester.tap(find.text('完全復元'));
    expect(backups, 1);
    expect(restores, 1);
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('完全バックアップを作成').first,
    );
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
  });
}
