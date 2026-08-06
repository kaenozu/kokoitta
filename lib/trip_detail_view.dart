import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'image_decode.dart';
import 'photo.dart';

class TripDetailView extends StatelessWidget {
  const TripDetailView({
    required this.title,
    required this.photos,
    required this.onPhotoTap,
    super.key,
    this.capturedAtLabel,
    this.locationLabel,
    this.onShare,
    this.onAddPhotos,
    this.onMoveToUnassigned,
    this.onDelete,
    this.busyMessage,
  });

  final String title;
  final List<Photo> photos;
  final String? capturedAtLabel;
  final String? locationLabel;
  final ValueChanged<int> onPhotoTap;
  final VoidCallback? onShare;
  final VoidCallback? onAddPhotos;
  final VoidCallback? onMoveToUnassigned;
  final VoidCallback? onDelete;
  final String? busyMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.maybePop(context)),
        title: Text(title),
        actions: <Widget>[
          PopupMenuButton<_TripDetailAction>(
            tooltip: '$titleの管理メニュー',
            onSelected: (action) => switch (action) {
              _TripDetailAction.share => onShare?.call(),
              _TripDetailAction.move => onMoveToUnassigned?.call(),
              _TripDetailAction.delete => onDelete?.call(),
            },
            itemBuilder: (context) => <PopupMenuEntry<_TripDetailAction>>[
              PopupMenuItem<_TripDetailAction>(
                value: _TripDetailAction.share,
                enabled: onShare != null,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.share_outlined),
                  title: Text('写真を共有'),
                ),
              ),
              PopupMenuItem<_TripDetailAction>(
                value: _TripDetailAction.move,
                enabled: onMoveToUnassigned != null,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.drive_file_move_outline),
                  title: Text('旅行未設定へ移動'),
                ),
              ),
              PopupMenuItem<_TripDetailAction>(
                value: _TripDetailAction.delete,
                enabled: onDelete != null,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '写真も削除',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final crossAxisCount = textScale > 1.3
              ? 2
              : switch (constraints.maxWidth) {
                  >= 1000 => 6,
                  >= 720 => 4,
                  >= 420 => 3,
                  _ => 2,
                };
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(KokoittaSpacing.md),
                  child: _TripHero(
                    title: title,
                    photos: photos,
                    capturedAtLabel: capturedAtLabel,
                    locationLabel: locationLabel,
                    onAddPhotos: onAddPhotos,
                    busyMessage: busyMessage,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  KokoittaSpacing.md,
                  0,
                  KokoittaSpacing.md,
                  KokoittaSpacing.xl,
                ),
                sliver: photos.isEmpty
                    ? const SliverToBoxAdapter(
                        child: KokoittaStatePanel(
                          tone: KokoittaStateTone.neutral,
                          title: 'まだ写真がありません',
                          message: 'この旅行へ写真を追加すると、ここに思い出が並びます。',
                        ),
                      )
                    : SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: KokoittaSpacing.xs,
                          mainAxisSpacing: KokoittaSpacing.xs,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _PhotoGridTile(
                            photo: photos[index],
                            index: index,
                            total: photos.length,
                            tripTitle: title,
                            onTap: () => onPhotoTap(index),
                          ),
                          childCount: photos.length,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TripHero extends StatelessWidget {
  const _TripHero({
    required this.title,
    required this.photos,
    required this.capturedAtLabel,
    required this.locationLabel,
    required this.onAddPhotos,
    required this.busyMessage,
  });

  final String title;
  final List<Photo> photos;
  final String? capturedAtLabel;
  final String? locationLabel;
  final VoidCallback? onAddPhotos;
  final String? busyMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KokoittaSectionHeader(
          title: title,
          supportingText: <String>[
            '${photos.length}枚の写真',
            ?capturedAtLabel,
            ?locationLabel,
          ].join('・'),
          trailing: KokoittaActionButton(
            label: '写真を追加',
            icon: Icons.add_a_photo_outlined,
            onPressed: onAddPhotos,
          ),
        ),
        if (busyMessage != null) ...<Widget>[
          const SizedBox(height: KokoittaSpacing.md),
          KokoittaStatePanel(
            tone: KokoittaStateTone.progress,
            title: '処理中です',
            message: busyMessage,
            busy: true,
            liveRegion: true,
          ),
        ],
      ],
    );
  }
}

class _PhotoGridTile extends StatelessWidget {
  const _PhotoGridTile({
    required this.photo,
    required this.index,
    required this.total,
    required this.tripTitle,
    required this.onTap,
  });

  final Photo photo;
  final int index;
  final int total;
  final String tripTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      image: true,
      label: '$tripTitleの写真 ${index + 1} / $total。拡大表示',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(KokoittaRadius.small),
          child: InkWell(
            onTap: onTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dimension = thumbnailDecodeDimension(
                  logicalWidth: constraints.maxWidth,
                  logicalHeight: constraints.maxHeight,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                );
                return Image.file(
                  photo.file,
                  fit: BoxFit.cover,
                  cacheWidth: dimension,
                  errorBuilder: (_, _, _) => const KokoittaPhotoPlaceholder(
                    state: KokoittaPhotoPlaceholderState.missing,
                    aspect: KokoittaImageAspect.square,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum _TripDetailAction { share, move, delete }
