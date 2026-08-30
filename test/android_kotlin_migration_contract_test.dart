import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android build uses AGP built-in Kotlin with the supported Flutter DSL',
    () {
      final properties = File('android/gradle.properties').readAsStringSync();
      final settings = File('android/settings.gradle.kts').readAsStringSync();
      final wrapper = File(
        'android/gradle/wrapper/gradle-wrapper.properties',
      ).readAsStringSync();
      final rootBuild = File('android/build.gradle.kts').readAsStringSync();
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final ci = File('.github/workflows/ci.yml').readAsStringSync();
      final release = File('.github/workflows/release.yml').readAsStringSync();

      // Issue #133 is the Built-in Kotlin migration. Flutter 3.47 supports that
      // path, but its own Gradle plugin still needs the separate AGP newDsl
      // compatibility opt-out. Keep KGP on the plugin classpath with apply=false
      // as the Flutter 3.47 template does; the app module must not apply it.
      expect(properties, isNot(contains('android.builtInKotlin=false')));
      expect(properties, contains('android.newDsl=false'));
      expect(
        settings,
        contains('id("com.android.application") version "9.1.0"'),
      );
      expect(
        settings,
        contains(
          'id("org.jetbrains.kotlin.android") version "2.4.0" apply false',
        ),
      );
      expect(wrapper, contains('gradle-9.3.1-all.zip'));
      expect(
        rootBuild,
        isNot(contains('org.jetbrains.kotlin:kotlin-gradle-plugin')),
      );
      expect(appBuild, isNot(contains('org.jetbrains.kotlin.android')));
      expect(ci, contains("flutter-version: '3.47.1'"));
      expect(release, contains("flutter-version: '3.47.1'"));
      expect(ci, isNot(contains("flutter-version: '3.44.0'")));
      expect(release, isNot(contains("flutter-version: '3.44.0'")));
    },
  );
}
