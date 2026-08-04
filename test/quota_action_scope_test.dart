import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photo quota only disables photo-add actions', () {
    final source = File('lib/home_view.dart').readAsStringSync();

    expect(
      RegExp(
        r'bool get _isDisabled =>\s*_isLoading \|\| '
        r'_coordinator\.isBusy \|\| _isImportBusy;',
      ).hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(
        r'bool get _cannotAddPhotos =>\s*_isDisabled \|\| '
        r'_loadError != null \|\| _photoQuotaReached;',
      ).hasMatch(source),
      isTrue,
    );
    expect(
      source.contains('onPressed: _isDisabled ? null : _showBackupMenu'),
      isTrue,
    );
    expect(source.contains('enabled: !_isDisabled'), isTrue);
    expect(
      source.contains('onPressed: _cannotAddPhotos ? null : _addPhotos'),
      isTrue,
    );
  });
}
