import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('final UI QA matrix', () {
    testWidgets('settings supports viewport theme and text-scale matrix', (
      tester,
    ) async {
      final viewports = <Size>[
        const Size(360, 800),
        const Size(412, 915),
        const Size(800, 1200),
      ];
      final brightnesses = <Brightness>[
        Brightness.light,
        Brightness.dark,
      ];
      final textScales = <double>[1, 1.3, 2];

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;

      for (final viewport in viewports) {
        for (final brightness in brightnesses) {
          for (final textScale in textScales) {
            tester.view.physicalSize = viewport;
            await tester.pumpWidget(
              MaterialApp(
                theme: buildKokoittaTheme(Brightness.light),
                darkTheme: buildKokoittaTheme(Brightness.dark),
                themeMode: brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: SettingsBackupView(
                    isBusy: false,
                    canCreateBackup: true,
                    canRestore: true,
                    lastResult: 'バックアップは正常に完了しました。',
                    onCreateBackup: () {},
                    onRestore: () {},
                  ),
                ),
              ),
            );
            await tester.pump();

            expect(find.text('設定'), findsOneWidget);
            expect(find.text('完全バックアップを作成'), findsOneWidget);
            expect(find.text('完全復元'), findsOneWidget);
            expect(find.byType(Scrollable), findsWidgets);
            expect(tester.takeException(), isNull);
          }
        }
      }
    });

    testWidgets('state tones remain explicit and readable without color alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKokoittaTheme(Brightness.light),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  KokoittaStatePanel(
                    tone: KokoittaStateTone.progress,
                    title: '読み込み中',
                    message: '写真を確認しています。',
                    busy: true,
                    liveRegion: true,
                  ),
                  KokoittaStatePanel(
                    tone: KokoittaStateTone.success,
                    title: '完了',
                    message: '3件を保存しました。',
                    liveRegion: true,
                  ),
                  KokoittaStatePanel(
                    tone: KokoittaStateTone.warning,
                    title: '一部失敗',
                    message: '2件を保存し、1件を保存できませんでした。',
                    liveRegion: true,
                  ),
                  KokoittaStatePanel(
                    tone: KokoittaStateTone.error,
                    title: 'エラー',
                    message: 'データを読み込めませんでした。',
                    liveRegion: true,
                  ),
                  KokoittaStatePanel(
                    tone: KokoittaStateTone.quota,
                    title: '保存上限',
                    message: '不要な写真を整理してください。',
                    liveRegion: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final title in <String>[
        '読み込み中',
        '完了',
        '一部失敗',
        'エラー',
        '保存上限',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('primary settings actions meet tap-target and callback contract', (
      tester,
    ) async {
      var backupCalls = 0;
      var restoreCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKokoittaTheme(Brightness.light),
          home: Scaffold(
            body: SettingsBackupView(
              isBusy: false,
              canCreateBackup: true,
              canRestore: true,
              onCreateBackup: () => backupCalls += 1,
              onRestore: () => restoreCalls += 1,
            ),
          ),
        ),
      );
      await tester.pump();

      final backupTile = find.widgetWithText(
        ListTile,
        '完全バックアップを作成',
      );
      final restoreTile = find.widgetWithText(ListTile, '完全復元');

      expect(tester.getSize(backupTile).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(restoreTile).height, greaterThanOrEqualTo(48));

      await tester.tap(find.text('完全バックアップを作成'));
      await tester.tap(find.text('完全復元'));
      expect(backupCalls, 1);
      expect(restoreCalls, 1);
    });

    testWidgets('busy state disables conflicting operations with explanation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKokoittaTheme(Brightness.dark),
          home: Scaffold(
            body: SettingsBackupView(
              isBusy: true,
              canCreateBackup: true,
              canRestore: true,
              busyMessage: '復元データを検証しています。',
              onCreateBackup: () {},
              onRestore: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('データを処理しています'), findsOneWidget);
      expect(find.text('復元データを検証しています。'), findsOneWidget);
      final backup = tester.widget<ListTile>(
        find.widgetWithText(ListTile, '完全バックアップを作成'),
      );
      final restore = tester.widget<ListTile>(
        find.widgetWithText(ListTile, '完全復元'),
      );
      expect(backup.enabled, isFalse);
      expect(restore.enabled, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
