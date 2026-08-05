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
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 72),
        SizedBox(height: 8),
        Text('写真を表示できません'),
      ],
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
  });

  final List<Photo> photos;
  final int initialIndex;
  final PhotoViewerImageBuilder? imageBuilder;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  PageController? _pageController;
  final Map<int, TransformationController> _transformations = {};
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
        appBar: AppBar(title: const Text('写真')),
        body: const Center(child: Text('写真がありません')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('写真 ${_currentIndex + 1} / ${widget.photos.length}'),
      ),
      body: PageView.builder(
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
            return Semantics(
              container: true,
              image: true,
              label:
                  '写真 ${index + 1} / ${widget.photos.length}。ダブルタップで拡大または元に戻す',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => _toggleZoom(index),
                child: InteractiveViewer(
                  key: ValueKey('photo-viewer-$index'),
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
            );
          },
        ),
      ),
    );
  }
}
