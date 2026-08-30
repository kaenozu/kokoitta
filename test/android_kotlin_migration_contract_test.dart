import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android build uses AGP built-in Kotlin with the supported Flutter DSL',
    () {
      final properties = File('android/gradle.properties').readAsStringSync();
      final settings = File('android/settings.gradle.kts').readAsStringSync();
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final ci = File('.github/workflows/ci.yml').readAsStringSync();
      final release = File('.github/workflows/release.yml').readAsStringSync();

      // Issue #133 is the Built-in Kotlin migration. Flutter 3.47 supports that
      // opt-in, but Flutter's own Gradle plugin has not completed the separate
      // AGP newDsl migration yet, so only that compatibility opt-out remains.
      expect(properties, isNot(contains('android.builtInKotlin=false')));
      expect(properties, contains('android.newDsl=false'));
      expect(
        settings,
        contains('id("com.android.application") version "9.0.1"'),
      );
      expect(appBuild, isNot(contains('org.jetbrains.kotlin.android')));
      expect(ci, contains("flutter-version: '3.47.1'"));
      expect(release, contains("flutter-version: '3.47.1'"));
      expect(ci, isNot(contains("flutter-version: '3.44.0'")));
      expect(release, isNot(contains("flutter-version: '3.44.0'")));
    },
  );
}
