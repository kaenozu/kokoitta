import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing photo discard confirmation never renders the private path', () {
    final source = File('lib/home_data.dart').readAsStringSync();
    final start = source.indexOf('Future<bool?> _confirmDiscard');
    final end = source.indexOf(
      'Future<_CopiedImportResult> _copyPickedImages',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final dialogSource = source.substring(start, end);
    expect(dialogSource, isNot(contains('missing.path')));
    expect(dialogSource, contains('この写真の記録が保存データから削除されます'));
  });
}
