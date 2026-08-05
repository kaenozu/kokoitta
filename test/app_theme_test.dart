import 'package:flutter/material.dart';
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
    expect(
      Theme.of(tester.element(find.text('theme probe'))).brightness,
      Brightness.dark,
    );
  });
}
