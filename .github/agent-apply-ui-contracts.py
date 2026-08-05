from pathlib import Path
import re
import subprocess

Path('lib/app_theme.dart').write_text('''import 'package:flutter/material.dart';

ThemeData buildKokoittaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: isDark ? const Color(0xff8fd3aa) : const Color(0xff1b4332),
    brightness: brightness,
  ).copyWith(
    primary: isDark ? const Color(0xffb5e8c8) : const Color(0xff1b4332),
    secondary: isDark ? const Color(0xffffa58f) : const Color(0xffff7051),
    surface: isDark ? const Color(0xff121714) : const Color(0xfffcf9f8),
  );
  final scaffold = scheme.surface;
  final card = isDark ? const Color(0xff1c2420) : Colors.white;
  final navigation = isDark ? const Color(0xff18201c) : const Color(0xfff0eded);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 1,
      shadowColor: isDark ? Colors.black54 : const Color(0x221b4332),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: navigation,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
    ),
    useMaterial3: true,
  );
}
''', encoding='utf-8')

Path('lib/photo_quota.dart').write_text('''import 'package:flutter/material.dart';

const int photoQuotaLimit = 300;

class PhotoQuotaStatus {
  const PhotoQuotaStatus({required this.count, this.limit = photoQuotaLimit});

  final int count;
  final int limit;

  int get normalizedCount => count < 0 ? 0 : count;
  int get remaining => (limit - normalizedCount).clamp(0, limit);
  bool get reached => normalizedCount >= limit;
  bool get exceeded => normalizedCount > limit;

  String get title => '写真 $normalizedCount / $limit枚';
  String get message => reached
      ? exceeded
            ? '上限を${normalizedCount - limit}枚超えています。既存の写真を整理してください'
            : '上限に達しています。既存の写真を整理してください'
      : '残り $remaining枚';
  String get semanticsLabel =>
      '写真使用数 $normalizedCount枚、上限 $limit枚、残り$remaining枚、${reached ? '写真追加不可' : '写真追加可能'}';
}

class PhotoQuotaCard extends StatelessWidget {
  const PhotoQuotaCard({super.key, required this.status});

  final PhotoQuotaStatus status;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      label: status.semanticsLabel,
      child: Card(
        child: ListTile(
          leading: Icon(
            status.reached ? Icons.block : Icons.photo_library_outlined,
            semanticLabel: status.reached ? '写真追加不可' : '写真追加可能',
          ),
          title: Text(status.title),
          subtitle: Text(status.message),
        ),
      ),
    );
  }
}
''', encoding='utf-8')

Path('lib/photo_viewer.dart').write_text('''import 'dart:io';

import 'package:flutter/material.dart';

import 'image_decode.dart';
import 'photo.dart';

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  final List<Photo> photos;
  final int initialIndex;

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
              label: '写真 ${index + 1} / ${widget.photos.length}。ダブルタップで拡大または元に戻す',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => _toggleZoom(index),
                child: InteractiveViewer(
                  key: ValueKey('photo-viewer-$index'),
                  transformationController: transformation,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(
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
''', encoding='utf-8')

main = Path('lib/main.dart')
text = main.read_text(encoding='utf-8')
text = text.replace("import 'app_data_operations.dart';\n", "import 'app_data_operations.dart';\nimport 'app_theme.dart';\n", 1)
text = text.replace("import 'photo.dart';\n", "import 'photo.dart';\nimport 'photo_quota.dart';\nimport 'photo_viewer.dart';\n", 1)
pattern = re.compile(r'''      theme: ThemeData\(.*?      themeMode: ThemeMode\.system,''', re.S)
replacement = '''      theme: buildKokoittaTheme(Brightness.light),
      darkTheme: buildKokoittaTheme(Brightness.dark),
      themeMode: ThemeMode.system,'''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f'theme block replacements={count}')
main.write_text(text, encoding='utf-8')

home = Path('lib/home_view.dart')
text = home.read_text(encoding='utf-8')
text = text.replace('  static const _photoQuota = 300;\n', '  static const _photoQuota = photoQuotaLimit;\n', 1)
text = text.replace('  bool get _photoQuotaReached => _photoCount >= _photoQuota;\n', "  PhotoQuotaStatus get _quotaStatus => PhotoQuotaStatus(count: _photoCount);\n\n  bool get _photoQuotaReached => _quotaStatus.reached;\n", 1)
quota_pattern = re.compile(r'''        Semantics\(\n          liveRegion: true,\n          label:.*?        const SizedBox\(height: 28\),''', re.S)
quota_replacement = '''        PhotoQuotaCard(status: _quotaStatus),
        const SizedBox(height: 28),'''
text, count = quota_pattern.subn(quota_replacement, text, count=1)
if count != 1:
    raise SystemExit(f'quota block replacements={count}')
text = text.replace('''        builder: (_) =>
            _PhotoViewer(photos: photos, initialIndex: initialIndex),
''', '''        builder: (_) =>
            PhotoViewer(photos: photos, initialIndex: initialIndex),
''', 1)
viewer_start = text.index('\nclass _PhotoViewer extends StatefulWidget')
text = text[:viewer_start].rstrip() + '\n'
home.write_text(text, encoding='utf-8')

Path('test/app_theme_test.dart').write_text('''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/app_theme.dart';

void main() {
  test('light and dark themes use their requested brightness', () {
    final light = buildKokoittaTheme(Brightness.light);
    final dark = buildKokoittaTheme(Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
  });

  testWidgets('MaterialApp follows system brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKokoittaTheme(Brightness.light),
        darkTheme: buildKokoittaTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const Scaffold(body: Text('theme probe')),
      ),
    );
    expect(Theme.of(tester.element(find.text('theme probe'))).brightness, Brightness.dark);
  });
}
''', encoding='utf-8')

Path('test/photo_quota_test.dart').write_text('''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/photo_quota.dart';

void main() {
  for (final entry in <int, (int, bool, bool)>{
    0: (300, false, false),
    299: (1, false, false),
    300: (0, true, false),
    301: (0, true, true),
  }.entries) {
    test('quota ${entry.key} has safe boundaries', () {
      final status = PhotoQuotaStatus(count: entry.key);
      expect(status.remaining, entry.value.$1);
      expect(status.reached, entry.value.$2);
      expect(status.exceeded, entry.value.$3);
    });
  }

  testWidgets('quota card exposes count, remaining and add availability', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PhotoQuotaCard(status: PhotoQuotaStatus(count: 299))),
      ),
    );
    expect(find.text('写真 299 / 300枚'), findsOneWidget);
    expect(find.text('残り 1枚'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(PhotoQuotaCard)),
      matchesSemantics(
        label: '写真使用数 299枚、上限 300枚、残り1枚、写真追加可能',
        isLiveRegion: true,
      ),
    );
  });
}
''', encoding='utf-8')

Path('test/photo_viewer_test.dart').write_text('''import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/photo.dart';
import 'package:kokoitta_app/photo_viewer.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('empty viewer stays navigable', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PhotoViewer(photos: [], initialIndex: 0)),
    );
    expect(find.text('写真がありません'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('opens requested page, swipes and toggles double-tap zoom', (tester) async {
    final directory = await Directory.systemTemp.createTemp('photo-viewer-test-');
    addTearDown(() => directory.delete(recursive: true));
    final first = File('${directory.path}/first.png')..writeAsBytesSync(_png);
    final second = File('${directory.path}/second.png')..writeAsBytesSync(_png);
    final photos = [Photo.fromFile(first, id: 'first'), Photo.fromFile(second, id: 'second')];

    await tester.pumpWidget(
      MaterialApp(home: PhotoViewer(photos: photos, initialIndex: 1)),
    );
    await tester.pump();
    expect(find.text('写真 2 / 2'), findsOneWidget);

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('photo-viewer-1')),
    );
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    await tester.doubleTap(find.byKey(const ValueKey('photo-viewer-1')));
    await tester.pump();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(2));

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('写真 1 / 2'), findsOneWidget);
  });

  testWidgets('missing file shows a recoverable fallback', (tester) async {
    final photo = Photo.fromFile(File('/definitely/missing/photo.jpg'), id: 'missing');
    await tester.pumpWidget(
      MaterialApp(home: PhotoViewer(photos: [photo], initialIndex: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('写真を表示できません'), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
''', encoding='utf-8')

Path('.github/workflows/ci.yml').write_bytes(
    subprocess.check_output(['git', 'show', 'origin/main:.github/workflows/ci.yml'])
)
Path(__file__).unlink(missing_ok=True)
