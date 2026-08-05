import 'package:flutter/material.dart';

ThemeData buildKokoittaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
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
