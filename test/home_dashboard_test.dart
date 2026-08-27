import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';
import 'package:kokoitta_app/monetization/ad_banner.dart';
import 'package:kokoitta_app/offline_japan_map.dart';

void main() {
  Future<void> setSurface(
    WidgetTester tester, {
    required Size size,
    double devicePixelRatio = 1,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize = size * devicePixelRatio;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
  }

  Widget buildDashboard({
    Map<String, String> states = const <String, String>{},
    HomePrefectureSummary summary = const HomePrefectureSummary(
      visited: 0,
      planned: 0,
      unvisited: 47,
    ),
    HomeDashboardQuota quota = const HomeDashboardQuota(count: 0, limit: 300),
    int photoCount = 0,
    List<HomeRecentTripItem> recentTrips = const <HomeRecentTripItem>[],
    HomeDashboardOperation? operation,
    String? addDisabledReason,
    bool addEnabled = true,
    Brightness brightness = Brightness.light,
    double textScale = 1,
    int missingPhotoCount = 0,
    VoidCallback? onMissingPhotosTap,
  }) {
    return MaterialApp(
      theme: buildKokoittaTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: PrefectureMapActions(
            onTap: (_, _) async {},
            child: HomeMapDashboard(
              prefectureStates: states,
              prefectureSummary: summary,
              quota: quota,
              photoCount: photoCount,
              recentTrips: recentTrips,
              operation: operation,
              addDisabledReason: addDisabledReason,
              onAddPhotos: addEnabled ? () {} : null,
              onShowAllTrips: () {},
              onShowPrefectureList: () {},
              onRestoreBackup: () {},
              onOpenSettings: null,
              missingPhotoCount: missingPhotoCount,
              onMissingPhotosTap: onMissingPhotosTap,
            ),
          ),
        ),
      ),
    );
  }

  test('prefecture summary requires exactly 47 entries', () {
    expect(
      () => HomePrefectureSummary(visited: 1, planned: 1, unvisited: 44),
      throwsAssertionError,
    );
    expect(
      const HomePrefectureSummary(
        visited: 12,
        planned: 4,
        unvisited: 31,
      ).semanticLabel,
      '訪問済み12、計画中4、未訪問31、合計47都道府県',
    );
  });

  testWidgets('semantic colors fall back for plain Material themes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) => ColoredBox(
            key: const ValueKey<String>('semantic-color-fallback'),
            color: context.kokoittaColors.successContainer,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('semantic-color-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('360x800 at 200 percent text keeps one primary photo CTA', (
    tester,
  ) async {
    await setSurface(tester, size: const Size(360, 800));
    await tester.pumpWidget(buildDashboard(textScale: 2));
    await tester.pump();

    expect(find.text('写真からつくるおでかけ地図'), findsOneWidget);
    expect(find.text('写真を追加'), findsOneWidget);
    expect(find.text('都道府県一覧で設定'), findsOneWidget);
    expect(find.text('バックアップから復元'), findsOneWidget);
    expect(find.byType(OfflineJapanMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('412x915 shows map summary and recent trips without overflow', (
    tester,
  ) async {
    await setSurface(tester, size: const Size(412, 915));
    final trips = List<HomeRecentTripItem>.generate(
      3,
      (index) => HomeRecentTripItem(
        title: '長い旅行タイトル ${index + 1} と家族の思い出',
        photoCount: index + 2,
        image: const KokoittaPhotoPlaceholder(
          state: KokoittaPhotoPlaceholderState.empty,
          aspect: KokoittaImageAspect.wide,
        ),
        onTap: () {},
      ),
    );
    await tester.pumpWidget(
      buildDashboard(
        states: const <String, String>{
          '北海道': 'visited',
          '埼玉県': 'visited',
          '群馬県': 'transit',
        },
        summary: const HomePrefectureSummary(
          visited: 2,
          planned: 1,
          unvisited: 44,
        ),
        quota: const HomeDashboardQuota(count: 9, limit: 300),
        photoCount: 9,
        recentTrips: trips,
      ),
    );
    await tester.pump();

    expect(find.text('訪問済み 2'), findsOneWidget);
    expect(find.text('計画中 1'), findsOneWidget);
    expect(find.text('未訪問 44'), findsOneWidget);
    expect(find.text('写真を追加'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('長い旅行タイトル 3 と家族の思い出'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('長い旅行タイトル 3 と家族の思い出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet uses the same navigation hierarchy without overflow', (
    tester,
  ) async {
    await setSurface(tester, size: const Size(1200, 900));
    await tester.pumpWidget(
      buildDashboard(
        photoCount: 4,
        recentTrips: <HomeRecentTripItem>[
          HomeRecentTripItem(
            title: '夏休み',
            photoCount: 4,
            image: const KokoittaPhotoPlaceholder(
              state: KokoittaPhotoPlaceholderState.empty,
              aspect: KokoittaImageAspect.wide,
            ),
            onTap: () {},
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(OfflineJapanMap), findsOneWidget);
    expect(find.text('写真を追加'), findsOneWidget);
    expect(find.text('最近の旅行'), findsOneWidget);
    expect(find.text('夏休み'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy and quota states explain why photo add is disabled', (
    tester,
  ) async {
    await setSurface(tester, size: const Size(412, 915));
    await tester.pumpWidget(
      buildDashboard(
        quota: const HomeDashboardQuota(count: 300, limit: 300),
        photoCount: 300,
        addEnabled: false,
        addDisabledReason: '処理が完了すると写真を追加できます。',
        operation: HomeDashboardOperation(
          title: '写真を追加しています',
          message: '2 / 4枚を処理しています。',
          processed: 2,
          total: 4,
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '写真を追加'),
    );
    expect(addButton.onPressed, isNull);
    expect(find.text('写真を追加しています'), findsOneWidget);
    expect(find.text('キャンセル'), findsOneWidget);
    expect(find.text('写真の保存上限に達しました'), findsOneWidget);
    expect(find.text('写真を整理'), findsOneWidget);
    expect(find.text('設定を開く'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map and summary expose state through labels and controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await setSurface(tester, size: const Size(412, 915));
    await tester.pumpWidget(
      buildDashboard(
        states: const <String, String>{'北海道': 'visited', '埼玉': 'transit'},
        summary: const HomePrefectureSummary(
          visited: 1,
          planned: 1,
          unvisited: 45,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('訪問済み1、計画中1、未訪問45、合計47都道府県'), findsWidgets);
    expect(find.bySemanticsLabel('北海道、訪問済み。タップすると状態を選択'), findsOneWidget);
    expect(find.bySemanticsLabel('埼玉県、通過。タップすると状態を選択'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('missing photos banner shows count and opens recovery', (
    tester,
  ) async {
    var tapped = false;
    await setSurface(tester, size: const Size(412, 915));
    await tester.pumpWidget(
      buildDashboard(
        missingPhotoCount: 3,
        onMissingPhotosTap: () => tapped = true,
      ),
    );
    await tester.pump();

    expect(find.text('写真が3枚見つかりませんでした'), findsOneWidget);
    expect(find.text('端末内から移動・削除された可能性があります。タップして確認・復旧'), findsOneWidget);

    await tester.tap(find.text('写真が3枚見つかりませんでした'));
    await tester.pump();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing photos banner is hidden when count is zero', (
    tester,
  ) async {
    await setSurface(tester, size: const Size(412, 915));
    await tester.pumpWidget(
      buildDashboard(missingPhotoCount: 0, onMissingPhotosTap: () {}),
    );
    await tester.pump();

    expect(find.textContaining('見つかりませんでした'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home dashboard keeps a non-blocking free monetization notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        home: const Scaffold(body: MonetizationBanner()),
      ),
    );
    await tester.pump();

    expect(find.text('広告で無料提供を続けています'), findsOneWidget);
    expect(find.text('写真の追加や地図の利用は無料です。広告が読み込めない場合もそのまま使えます。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('monetization-banner')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
