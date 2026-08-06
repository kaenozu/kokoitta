import 'dart:io';

import 'package:flutter/material.dart';

import 'image_decode.dart';
import 'photo.dart';

typedef PhotoViewerImageBuilder =
    Widget Function(
      BuildContext context,
      File file,
      int cacheWidth,
      String semanticLabel,
    );

class PhotoLoadFallback extends StatelessWidget {
  const PhotoLoadFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '写真を表示できません。戻る操作は利用できます',
      child: const ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.broken_image_outlined, size: 72),
            SizedBox(height: 8),
            Text('写真を表示できません'),
          ],
        ),
      ),
    );
  }
}

Widget _defaultPhotoViewerImageBuilder(
  BuildContext context,
  File file,
  int cacheWidth,
  String semanticLabel,
) {
  return Image.file(
    file,
    fit: BoxFit.contain,
    cacheWidth: cacheWidth,
    semanticLabel: semanticLabel,
    errorBuilder: (_, _, _) => const PhotoLoadFallback(),
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.imageBuilder,
    this.title,
    this.onShare,
    this.onDelete,
  });

  final List<Photo> photos;
  final int initialIndex;
  final PhotoViewerImageBuilder? imageBuilder;
  final String? title;
  final ValueChanged<Photo>? onShare;
  final ValueChanged<Photo>? onDelete;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  PageController? _pageController;
  final Map<int, TransformationController> _transformations =
      <int, TransformationController>{};
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.photos.isNotEmpty) {
      _currentIndex = widget.initialIndex.clamp(0, widget.photos.length - 1);
      _pageController = PageController(initialPage: _currentIndex);
    }
  }

  TransformationController _transformationFor(int index) =>
      _transformations.putIfAbsent(index, TransformationController.new);

  void _toggleZoom(int index) {
    final controller = _transformationFor(index);
    final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
    controller.value = zoomed
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(2.5, 2.5, 1);
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= widget.photos.length) return;
    await _pageController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    for (final controller in _transformations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title ?? '写真')),
        body: const Center(child: Text('写真がありません')),
      );
    }
    final current = widget.photos[_currentIndex];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Semantics(
          liveRegion: true,
          label: '写真 ${_currentIndex + 1} / ${widget.photos.length}',
          child: ExcludeSemantics(
            child: Text(
              '${widget.title ?? '写真'} ${_currentIndex + 1} / ${widget.photos.length}',
            ),
          ),
        ),
        actions: <Widget>[
          if (widget.onShare != null)
            IconButton(
              tooltip: '現在の写真を共有',
              onPressed: () => widget.onShare!(current),
              icon: const Icon(Icons.share_outlined),
            ),
          if (widget.onDelete != null)
            IconButton(
              tooltip: '現在の写真を削除',
              onPressed: () => widget.onDelete!(current),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => LayoutBuilder(
              builder: (context, constraints) {
                final dimension = fullscreenDecodeDimension(
                  logicalWidth: constraints.maxWidth,
                  logicalHeight: constraints.maxHeight,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                );
                final transformation = _transformationFor(index);
                final semanticLabel =
                    '写真 ${index + 1} / ${widget.photos.length}。ダブルタップで拡大または元に戻す';
                return Semantics(
                  container: true,
                  image: true,
                  label: semanticLabel,
                  onTap: () => _toggleZoom(index),
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () => _toggleZoom(index),
                      child: InteractiveViewer(
                        key: ValueKey<String>('photo-viewer-$index'),
                        transformationController: transformation,
                        minScale: 1,
                        maxScale: 4,
                        child: Center(
                          child:
                              (widget.imageBuilder ??
                              _defaultPhotoViewerImageBuilder)(
                                context,
                                File(widget.photos[index].file.path),
                                dimension,
                                '写真 ${index + 1}',
                              ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.photos.length > 1) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: '前の写真',
                  onPressed: _currentIndex == 0
                      ? null
                      : () => _goTo(_currentIndex - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SafeArea(
                child: IconButton.filledTonal(
                  tooltip: '次の写真',
                  onPressed: _currentIndex == widget.photos.length - 1
                      ? null
                      : () => _goTo(_currentIndex + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
