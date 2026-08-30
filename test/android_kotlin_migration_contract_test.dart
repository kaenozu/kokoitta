import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android build uses AGP built-in Kotlin defaults', () {
    final properties = File('android/gradle.properties').readAsStringSync();
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();

    expect(properties, isNot(contains('android.builtInKotlin=false')));
    expect(properties, isNot(contains('android.newDsl=false')));
    expect(settings, contains('id("com.android.application") version "9.0.1"'));
    expect(appBuild, isNot(contains('org.jetbrains.kotlin.android')));
  });
}
