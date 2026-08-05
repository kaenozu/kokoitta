from pathlib import Path

home = Path('lib/home_view.dart')
text = home.read_text(encoding='utf-8')
text = text.replace('  static const _photoQuota = photoQuotaLimit;\n', '', 1)
home.write_text(text, encoding='utf-8')

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
test.write_text(text.replace(old, new, 1), encoding='utf-8')

Path('.ci-trigger-pr78').unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
