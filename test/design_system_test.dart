import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';

void main() {
  test('light and dark themes expose one semantic token source', () {
    final light = buildKokoittaTheme(Brightness.light);
    final dark = buildKokoittaTheme(Brightness.dark);
    final lightColors = light.extension<KokoittaSemanticColors>();
    final darkColors = dark.extension<KokoittaSemanticColors>();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(lightColors, isNotNull);
    expect(darkColors, isNotNull);
    expect(lightColors!.visited, isNot(lightColors.unvisited));
    expect(lightColors.planned, isNot(lightColors.visited));
    expect(darkColors!.visited, isNot(darkColors.unvisited));
    expect(lightColors.destructive, light.colorScheme.error);
    expect(darkColors.destructive, dark.colorScheme.error);

    final copied = lightColors.copyWith(focus: Colors.purple);
    expect(copied.focus, Colors.purple);
    expect(copied.visited, lightColors.visited);
    expect(lightColors.lerp(darkColors, 0.5), isA<KokoittaSemanticColors>());
  });

  test('spacing radius and motion contracts remain stable', () {
    expect(
      <double>[
        KokoittaSpacing.xxs,
        KokoittaSpacing.xs,
        KokoittaSpacing.sm,
        KokoittaSpacing.md,
        KokoittaSpacing.lg,
        KokoittaSpacing.xl,
        KokoittaSpacing.xxl,
      ],
      <double>[4, 8, 12, 16, 24, 32, 48],
    );
    expect(KokoittaRadius.small, 8);
    expect(KokoittaRadius.medium, 16);
    expect(KokoittaRadius.large, 24);
    expect(KokoittaRadius.pill, 999);
    expect(KokoittaMotion.short, const Duration(milliseconds: 150));
    expect(KokoittaMotion.medium, const Duration(milliseconds: 250));
    expect(KokoittaMotion.long, const Duration(milliseconds: 350));
    expect(KokoittaSize.minimumTapTarget, 48);
  });

  testWidgets('shared components fit 360px at 200 percent text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 360,
                  child: Padding(
                    padding: const EdgeInsets.all(KokoittaSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        KokoittaSectionHeader(
                          title: '最近の旅行と思い出の写真を振り返る',
                          supportingText: '文字を大きくしてもタイトルと操作を省略せず表示します。',
                          trailing: KokoittaActionButton(
                            label: 'すべて見る',
                            emphasis: KokoittaActionEmphasis.secondary,
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(height: KokoittaSpacing.md),
                        KokoittaStatePanel(
                          tone: KokoittaStateTone.warning,
                          title: '一部の写真を追加できませんでした',
                          message: '追加できた写真は保存されています。失敗した写真だけ再試行できます。',
                          liveRegion: true,
                          primaryAction: KokoittaActionButton(
                            label: '失敗分を再試行',
                            icon: Icons.refresh,
                            onPressed: () {},
                          ),
                          secondaryAction: KokoittaActionButton(
                            label: '完了して戻る',
                            emphasis: KokoittaActionEmphasis.secondary,
                            onPressed: () {},
                          ),
                        ),
                        const SizedBox(height: KokoittaSpacing.md),
                        KokoittaTripSummaryCard(
                          title: 'とても長い旅行タイトルでも固定高さを使わず安全に折り返す旅行',
                          semanticLabel: '旅行、長い旅行タイトル、写真12枚、開く',
                          onTap: () {},
                          metadata: const <Widget>[
                            Text('2026年7月20日から7月23日'),
                            Text('埼玉県・群馬県、写真12枚'),
                          ],
                        ),
                        const SizedBox(height: KokoittaSpacing.md),
                        const KokoittaPhotoPlaceholder(
                          state: KokoittaPhotoPlaceholderState.missing,
                        ),
                        const SizedBox(height: KokoittaSpacing.md),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: KokoittaSemanticIconButton(
                            icon: Icons.settings_outlined,
                            label: '設定を開く',
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('失敗分を再試行'), findsOneWidget);
    expect(find.text('写真を表示できません'), findsOneWidget);
  });

  testWidgets('state panel supports every semantic tone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (final tone in KokoittaStateTone.values)
                  Padding(
                    padding: const EdgeInsets.all(KokoittaSpacing.xs),
                    child: KokoittaStatePanel(
                      tone: tone,
                      title: tone.name,
                      message: '状態を色だけでなく文言とアイコンで説明します。',
                      busy: tone == KokoittaStateTone.progress,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final tone in KokoittaStateTone.values) {
      expect(find.text(tone.name), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('roles labels and tap actions are exposed to TalkBack', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var tripTapCount = 0;
    var menuTapCount = 0;
    var settingsTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                KokoittaSectionHeader(
                  title: '旅行',
                  trailing: KokoittaActionButton(
                    label: 'すべて見る',
                    onPressed: () {},
                  ),
                ),
                KokoittaStatePanel(
                  tone: KokoittaStateTone.progress,
                  title: '写真を追加しています',
                  message: '2 / 4枚',
                  liveRegion: true,
                  busy: true,
                ),
                KokoittaTripSummaryCard(
                  title: '夏休み',
                  semanticLabel: '旅行、夏休み、写真4枚、開く',
                  onTap: () => tripTapCount += 1,
                  overflow: IconButton(
                    tooltip: '旅行メニュー',
                    onPressed: () => menuTapCount += 1,
                    icon: const Icon(Icons.more_vert),
                  ),
                ),
                KokoittaSemanticIconButton(
                  icon: Icons.settings_outlined,
                  label: '設定を開く',
                  onPressed: () => settingsTapCount += 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final header = find.bySemanticsLabel('旅行');
    expect(header, findsOneWidget);
    expect(
      tester.getSemantics(header),
      matchesSemantics(label: '旅行', isHeader: true),
    );
    expect(
      tester.getSemantics(find.byType(KokoittaStatePanel)),
      matchesSemantics(isLiveRegion: true),
    );

    final trip = find.bySemanticsLabel('旅行、夏休み、写真4枚、開く');
    expect(trip, findsOneWidget);
    expect(
      tester.getSemantics(trip),
      matchesSemantics(
        label: '旅行、夏休み、写真4枚、開く',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    final menu = find.byTooltip('旅行メニュー');
    expect(menu, findsOneWidget);
    expect(
      tester
          .getSemantics(menu)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    final settings = find.byTooltip('設定を開く');
    expect(settings, findsOneWidget);
    expect(
      tester
          .getSemantics(settings)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(trip);
    tester
        .widget<IconButton>(
          find.ancestor(of: menu, matching: find.byType(IconButton)).first,
        )
        .onPressed!();
    tester
        .widget<IconButton>(
          find.ancestor(of: settings, matching: find.byType(IconButton)).first,
        )
        .onPressed!();
    await tester.pump();
    expect(tripTapCount, 1);
    expect(menuTapCount, 1);
    expect(settingsTapCount, 1);
    semantics.dispose();
  });
}
