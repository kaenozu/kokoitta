from pathlib import Path

home = Path('lib/home_view.dart')
text = home.read_text(encoding='utf-8')
text = text.replace('  static const _photoQuota = photoQuotaLimit;\n', '', 1)
home.write_text(text, encoding='utf-8')

viewer = Path('lib/photo_viewer.dart')
text = viewer.read_text(encoding='utf-8')
imports = """import 'image_decode.dart';
import 'photo.dart';

"""
replacement = """import 'image_decode.dart';
import 'photo.dart';

typedef PhotoViewerImageBuilder = Widget Function(
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

"""
if text.count(imports) != 1:
    raise SystemExit(f'viewer imports count={text.count(imports)}')
text = text.replace(imports, replacement, 1)
text = text.replace(
    """    required this.initialIndex,
  });

  final List<Photo> photos;
  final int initialIndex;
""",
    """    required this.initialIndex,
    this.imageBuilder,
  });

  final List<Photo> photos;
  final int initialIndex;
  final PhotoViewerImageBuilder? imageBuilder;
""",
    1,
)
old_image = """                    child: Image.file(
                      File(widget.photos[index].file.path),
                      fit: BoxFit.contain,
                      cacheWidth: dimension,
                      semanticLabel: '写真 ${index + 1}',
                      errorBuilder: (_, _, _) => const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined, size: 72),
                          SizedBox(height: 8),
                          Text('写真を表示できません'),
                        ],
                      ),
                    ),
"""
new_image = """                    child: (widget.imageBuilder ??
                            _defaultPhotoViewerImageBuilder)(
                      context,
                      File(widget.photos[index].file.path),
                      dimension,
                      '写真 ${index + 1}',
                    ),
"""
if text.count(old_image) != 1:
    raise SystemExit(f'image block count={text.count(old_image)}')
viewer.write_text(text.replace(old_image, new_image, 1), encoding='utf-8')

quota_test = Path('test/photo_quota_test.dart')
text = quota_test.read_text(encoding='utf-8')
text = text.replace(
    """    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
""",
    """    final semantics = tester.ensureSemantics();
""",
    1,
)
needle = """        isLiveRegion: true,
      ),
    );
  });
}
"""
replacement = """        isLiveRegion: true,
      ),
    );
    semantics.dispose();
  });
}
"""
if text.count(needle) != 1:
    raise SystemExit(f'quota semantics tail count={text.count(needle)}')
quota_test.write_text(text.replace(needle, replacement, 1), encoding='utf-8')

test = Path('test/photo_viewer_test.dart')
text = test.read_text(encoding='utf-8')
old = """    await tester.doubleTap(find.byKey(const ValueKey('photo-viewer-1')));
    await tester.pump();
"""
new = """    final target = find.byKey(const ValueKey('photo-viewer-1'));
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pump();
"""
if text.count(old) != 1:
    raise SystemExit(f'double-tap block count={text.count(old)}')
text = text.replace(old, new, 1)
text = text.replace(
    """    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
""",
    """    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
""",
    1,
)
old_missing = """    await tester.pumpWidget(
      MaterialApp(home: PhotoViewer(photos: [photo], initialIndex: 0)),
    );
    await tester.pumpAndSettle();
"""
new_missing = """    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [photo],
          initialIndex: 0,
          imageBuilder: (_, _, _, _) => const PhotoLoadFallback(),
        ),
      ),
    );
    await tester.pump();
"""
if text.count(old_missing) != 1:
    raise SystemExit(f'missing image block count={text.count(old_missing)}')
text = text.replace(old_missing, new_missing, 1)
test.write_text(text, encoding='utf-8')

Path('.ci-trigger-pr78').unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
