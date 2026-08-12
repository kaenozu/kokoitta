import 'package:flutter/material.dart';

import 'design/kokoitta_components.dart';
import 'design/kokoitta_design_system.dart';
import 'offline_japan_map.dart';

@immutable
class HomePrefectureSummary {
  const HomePrefectureSummary({
    required this.visited,
    required this.planned,
    required this.unvisited,
  }) : assert(visited >= 0),
       assert(planned >= 0),
       assert(unvisited >= 0),
       assert(visited + planned + unvisited == OfflineJapanMap.prefectureCount);

  final int visited;
  final int planned;
  final int unvisited;

  String get semanticLabel => '訪問済み$visited、計画中$planned、未訪問$unvisited、合計47都道府県';
}

@immutable
class HomeDashboardOperation {
  const HomeDashboardOperation({
    required this.title,
    required this.message,
    this.processed,
    this.total,
    this.onCancel,
  }) : assert(processed == null || processed >= 0),
       assert(total == null || total >= 0),
       assert(
         processed == null || total == null || processed <= total,
         'processed must not exceed total',
       );

  final String title;
  final String message;
  final int? processed;
  final int? total;
  final VoidCallback? onCancel;

  double? get progress {
    final expected = total;
    final current = processed;
    if (expected == null || current == null || expected <= 0) return null;
    return current / expected;
  }
}

@immutable
class HomeDashboardQuota {
  const HomeDashboardQuota({required this.count, required this.limit})
    : assert(count >= 0),
      assert(limit > 0);

  final int count;
  final int limit;

  bool get reached => count >= limit;
  int get remaining => count < limit ? limit - count : 0;
}

@immutable
class HomeRecentTripItem {
  const HomeRecentTripItem({
    required this.title,
    required this.photoCount,
    required this.image,
    required this.onTap,
  }) : assert(photoCount >= 0);

  final String title;
  final int photoCount;
  final Widget image;
  final VoidCallback onTap;

  String get semanticLabel => '旅行、$title、写真$photoCount枚、開く';
}

/// Presentation-only home screen.
///
/// Persistence, import, quota, deletion, and backup behavior stay in the
/// application state. This widget only establishes information hierarchy,
/// responsive layout, and accessibility order.
class HomeMapDashboard extends StatelessWidget {
  const HomeMapDashboard({
    required this.prefectureStates,
    required this.prefectureSummary,
    required this.quota,
    required this.photoCount,
    required this.recentTrips,
    required this.onAddPhotos,
    required this.onShowAllTrips,
    required this.onShowPrefectureList,
    required this.onRestoreBackup,
    required this.onOpenSettings,
    super.key,
    this.operation,
    this.addDisabledReason,
    this.missingPhotoCount = 0,
    this.onMissingPhotosTap,
  });

  final Map<String, String> prefectureStates;
  final HomePrefectureSummary prefectureSummary;
  final HomeDashboardQuota quota;
  final int photoCount;
  final List<HomeRecentTripItem> recentTrips;
  final VoidCallback? onAddPhotos;
  final VoidCallback onShowAllTrips;
  final VoidCallback? onShowPrefectureList;
  final VoidCallback? onRestoreBackup;
  final VoidCallback? onOpenSettings;
  final HomeDashboardOperation? operation;
  final String? addDisabledReason;

  /// 保存データが参照しているが、ファイルが存在しない写真の枚数。
  final int missingPhotoCount;

  /// 欠損写真の確認・復旧 UI を開くコールバック。null ならバナーを出さない。
  final VoidCallback? onMissingPhotosTap;

  bool get _isEmpty => photoCount == 0 && recentTrips.isEmpty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final twoPane = constraints.maxWidth >= 900 && textScale <= 1.3;
        final horizontalPadding = constraints.maxWidth < 420
            ? KokoittaSpacing.md
            : KokoittaSpacing.lg;
        final mapColumn = _buildMapColumn(context);
        final recentColumn = _buildRecentTrips(context);

        return ListView(
          key: const PageStorageKey<String>('home-map-dashboard'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            KokoittaSpacing.md,
            horizontalPadding,
            KokoittaSpacing.xxl,
          ),
          children: <Widget>[
            if (missingPhotoCount > 0 && onMissingPhotosTap != null)
              _buildMissingPhotosBanner(context),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: KokoittaSize.contentMaxWidth,
                ),
                child: twoPane
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 11, child: mapColumn),
                          const SizedBox(width: KokoittaSpacing.lg),
                          Expanded(flex: 9, child: recentColumn),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          mapColumn,
                          const SizedBox(height: KokoittaSpacing.xl),
                          recentColumn,
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMissingPhotosBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: KokoittaSpacing.md),
      child: Material(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(KokoittaRadius.medium),
        child: InkWell(
          onTap: onMissingPhotosTap,
          borderRadius: BorderRadius.circular(KokoittaRadius.medium),
          child: Padding(
            padding: const EdgeInsets.all(KokoittaSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.image_not_supported_outlined,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: KokoittaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '写真が$missingPhotoCount枚見つかりませんでした',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: KokoittaSpacing.xs),
                      Text(
                        '端末内から移動・削除された可能性があります。タップして確認・復旧',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onErrorContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapColumn(BuildContext context) {
    final activeOperation = operation;
    final supportingText = _isEmpty
        ? '写真を追加すると、日本地図と旅の思い出が端末の中で育ちます。'
        : '日本地図で旅の広がりを確認し、思い出の写真へ戻れます。';
    final stateActions = <Widget>[
      if (_isEmpty && onRestoreBackup != null)
        KokoittaActionButton(
          label: 'バックアップから復元',
          icon: Icons.restore_outlined,
          emphasis: KokoittaActionEmphasis.secondary,
          onPressed: onRestoreBackup,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KokoittaSectionHeader(
          title: '写真からつくるおでかけ地図',
          supportingText: supportingText,
        ),
        const SizedBox(height: KokoittaSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(KokoittaSpacing.sm),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: prefectureSummary.semanticLabel,
              child: OfflineJapanMap(states: prefectureStates),
            ),
          ),
        ),
        const SizedBox(height: KokoittaSpacing.md),
        Semantics(
          container: true,
          label: prefectureSummary.semanticLabel,
          child: ExcludeSemantics(
            child: Wrap(
              spacing: KokoittaSpacing.xs,
              runSpacing: KokoittaSpacing.xs,
              children: <Widget>[
                _SummaryMetric(
                  label: '訪問済み',
                  count: prefectureSummary.visited,
                  icon: Icons.check_circle_outline,
                  background: context.kokoittaColors.successContainer,
                  foreground: context.kokoittaColors.onSuccessContainer,
                ),
                _SummaryMetric(
                  label: '計画中',
                  count: prefectureSummary.planned,
                  icon: Icons.route_outlined,
                  background: Theme.of(context).colorScheme.secondaryContainer,
                  foreground: Theme.of(
                    context,
                  ).colorScheme.onSecondaryContainer,
                ),
                _SummaryMetric(
                  label: '未訪問',
                  count: prefectureSummary.unvisited,
                  icon: Icons.circle_outlined,
                  background: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  foreground: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KokoittaSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: KokoittaActionButton(
            label: '都道府県一覧で設定',
            icon: Icons.format_list_bulleted,
            emphasis: KokoittaActionEmphasis.secondary,
            onPressed: onShowPrefectureList,
          ),
        ),
        const SizedBox(height: KokoittaSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: KokoittaActionButton(
            label: '写真を追加',
            icon: Icons.add_a_photo_outlined,
            onPressed: onAddPhotos,
          ),
        ),
        if (addDisabledReason != null) ...[
          const SizedBox(height: KokoittaSpacing.xs),
          Text(
            addDisabledReason!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (stateActions.isNotEmpty) ...[
          const SizedBox(height: KokoittaSpacing.sm),
          Wrap(
            spacing: KokoittaSpacing.sm,
            runSpacing: KokoittaSpacing.sm,
            children: stateActions,
          ),
        ],
        if (activeOperation != null) ...[
          const SizedBox(height: KokoittaSpacing.md),
          KokoittaStatePanel(
            tone: KokoittaStateTone.progress,
            title: activeOperation.title,
            message: activeOperation.message,
            progress: activeOperation.progress,
            busy: true,
            liveRegion: true,
            secondaryAction: activeOperation.onCancel == null
                ? null
                : KokoittaActionButton(
                    label: 'キャンセル',
                    emphasis: KokoittaActionEmphasis.secondary,
                    onPressed: activeOperation.onCancel,
                  ),
          ),
        ],
        if (quota.reached) ...[
          const SizedBox(height: KokoittaSpacing.md),
          KokoittaStatePanel(
            tone: KokoittaStateTone.quota,
            title: '写真の保存上限に達しました',
            message: '${quota.count} / ${quota.limit}枚。旅行一覧で不要な写真を整理できます。',
            primaryAction: KokoittaActionButton(
              label: '写真を整理',
              icon: Icons.photo_library_outlined,
              onPressed: onShowAllTrips,
            ),
            secondaryAction: onOpenSettings == null
                ? null
                : KokoittaActionButton(
                    label: '設定を開く',
                    icon: Icons.settings_outlined,
                    emphasis: KokoittaActionEmphasis.secondary,
                    onPressed: onOpenSettings,
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildRecentTrips(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KokoittaSectionHeader(
          title: '最近の旅行',
          supportingText: recentTrips.isEmpty
              ? '写真を追加すると、ここに旅の思い出が並びます。'
              : '新しい思い出から最大3件を表示しています。',
          trailing: KokoittaActionButton(
            label: 'すべて見る',
            emphasis: KokoittaActionEmphasis.secondary,
            onPressed: onShowAllTrips,
          ),
        ),
        const SizedBox(height: KokoittaSpacing.md),
        if (recentTrips.isEmpty)
          const KokoittaStatePanel(
            tone: KokoittaStateTone.neutral,
            title: '旅行はまだありません',
            message: '上の「写真を追加」から、最初の思い出を地図に残せます。',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final columns = constraints.maxWidth >= 560 && textScale <= 1.3
                  ? 2
                  : 1;
              final gap = KokoittaSpacing.md;
              final itemWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: recentTrips
                    .map(
                      (item) => SizedBox(
                        width: itemWidth,
                        child: KokoittaTripSummaryCard(
                          title: item.title,
                          semanticLabel: item.semanticLabel,
                          onTap: item.onTap,
                          image: AspectRatio(
                            aspectRatio: KokoittaImageAspect.wide.ratio,
                            child: item.image,
                          ),
                          metadata: <Widget>[Text('${item.photoCount}枚の思い出')],
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.count,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(KokoittaRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KokoittaSpacing.sm,
          vertical: KokoittaSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: KokoittaSize.iconSmall, color: foreground),
            const SizedBox(width: KokoittaSpacing.xxs),
            Text(
              '$label $count',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
