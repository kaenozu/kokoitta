import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'photo.dart';

class TripListItem {
  const TripListItem({
    required this.title,
    required this.photoCount,
    required this.onTap,
    required this.image,
    this.capturedAtLabel,
    this.locationLabel,
    this.overflow,
    this.badge,
  });

  final String title;
  final int photoCount;
  final VoidCallback? onTap;
  final Widget image;
  final String? capturedAtLabel;
  final String? locationLabel;
  final Widget? overflow;
  final Widget? badge;

  String get semanticLabel {
    final details = <String>[
      title,
      '$photoCount枚の写真',
      ?capturedAtLabel,
      ?locationLabel,
    ];
    return '${details.join('、')}。詳細を開く';
  }
}

class KokoittaTripListView extends StatelessWidget {
  const KokoittaTripListView({
    required this.items,
    required this.onAddPhotos,
    required this.onRestoreBackup,
    super.key,
    this.unassigned,
    this.disabledReason,
  });

  final List<TripListItem> items;
  final TripListItem? unassigned;
  final VoidCallback? onAddPhotos;
  final VoidCallback? onRestoreBackup;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && unassigned == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(KokoittaSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: KokoittaStatePanel(
              tone: KokoittaStateTone.neutral,
              title: '最初の旅の思い出をつくりましょう',
              message: disabledReason ??
                  '写真を追加すると、撮影日や場所を手がかりに旅行としてまとめられます。',
              primaryAction: KokoittaActionButton(
                label: '写真を追加',
                icon: Icons.add_a_photo_outlined,
                onPressed: onAddPhotos,
              ),
              secondaryAction: KokoittaActionButton(
                label: 'バックアップから復元',
                icon: Icons.restore_outlined,
                emphasis: KokoittaActionEmphasis.secondary,
                onPressed: onRestoreBackup,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final twoColumns = constraints.maxWidth >= 760 && textScale <= 1.3;
        final contentWidth = constraints.maxWidth.clamp(0, 1120).toDouble();
        final cardWidth = twoColumns
            ? (contentWidth - KokoittaSpacing.md) / 2
            : contentWidth;
        final allItems = <TripListItem>[?unassigned, ...items];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(KokoittaSpacing.md),
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  KokoittaSectionHeader(
                    title: '旅行',
                    supportingText: '${items.length}件の旅行を保存しています',
                  ),
                  if (disabledReason != null) ...[
                    const SizedBox(height: KokoittaSpacing.md),
                    KokoittaStatePanel(
                      tone: KokoittaStateTone.warning,
                      title: '写真を追加できません',
                      message: disabledReason,
                    ),
                  ],
                  const SizedBox(height: KokoittaSpacing.md),
                  Wrap(
                    spacing: KokoittaSpacing.md,
                    runSpacing: KokoittaSpacing.md,
                    children: allItems
                        .map(
                          (item) => SizedBox(
                            width: cardWidth,
                            child: _TripListCard(item: item),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TripListCard extends StatelessWidget {
  const _TripListCard({required this.item});

  final TripListItem item;

  @override
  Widget build(BuildContext context) {
    final metadata = <Widget>[
      _MetadataLine(
        icon: Icons.photo_library_outlined,
        label: '${item.photoCount}枚の思い出',
      ),
      if (item.capturedAtLabel != null)
        _MetadataLine(
          icon: Icons.calendar_today_outlined,
          label: item.capturedAtLabel!,
        ),
      if (item.locationLabel != null)
        _MetadataLine(
          icon: Icons.place_outlined,
          label: item.locationLabel!,
        ),
    ];

    return KokoittaTripSummaryCard(
      title: item.title,
      semanticLabel: item.semanticLabel,
      onTap: item.onTap,
      image: item.image,
      metadata: metadata,
      badge: item.badge,
      overflow: item.overflow,
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: KokoittaSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

String? formatTripCapturedAt(List<Photo> photos) {
  final values = photos
      .map((photo) => photo.capturedAt)
      .whereType<DateTime>()
      .toList(growable: false)
    ..sort();
  if (values.isEmpty) return null;
  final first = values.first.toLocal();
  final last = values.last.toLocal();
  final firstLabel = _formatDate(first);
  final lastLabel = _formatDate(last);
  return firstLabel == lastLabel ? firstLabel : '$firstLabel〜$lastLabel';
}

String? formatTripLocations(List<Photo> photos) {
  final locations = <String>[];
  for (final photo in photos) {
    final value = photo.location?.trim();
    if (value == null || value.isEmpty || locations.contains(value)) continue;
    locations.add(value);
  }
  if (locations.isEmpty) return null;
  if (locations.length <= 2) return locations.join('・');
  return '${locations.take(2).join('・')} ほか${locations.length - 2}件';
}

String _formatDate(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';
