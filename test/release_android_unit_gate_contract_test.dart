import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release runs Android unit tests before signing secrets', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    const androidUnitStep =
        '      - name: Android unit tests\n'
        '        run: ./android/gradlew -p android :app:testDebugUnitTest --no-daemon';
    const signingStep = '      - name: Require signing secrets';
    const publishStep = '      - name: Publish GitHub Release';

    final androidIndex = workflow.indexOf(androidUnitStep);
    final signingIndex = workflow.indexOf(signingStep);
    final publishIndex = workflow.indexOf(publishStep);

    expect(androidIndex, greaterThanOrEqualTo(0));
    expect(signingIndex, greaterThan(androidIndex));
    expect(publishIndex, greaterThan(signingIndex));
  });
}
