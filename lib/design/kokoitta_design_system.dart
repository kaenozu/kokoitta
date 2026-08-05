import 'package:flutter/material.dart';

/// Spacing values shared by the application UI.
abstract final class KokoittaSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Radius values shared by cards, controls, sheets, and status surfaces.
abstract final class KokoittaRadius {
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
  static const double pill = 999;
}

/// Interactive dimensions. Visual icons may be smaller than their hit target.
abstract final class KokoittaSize {
  static const double iconSmall = 18;
  static const double icon = 24;
  static const double iconLarge = 44;
  static const double minimumTapTarget = 48;
  static const double contentMaxWidth = 1120;
}

/// Motion values for non-essential UI transitions.
abstract final class KokoittaMotion {
  static const Duration short = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration long = Duration(milliseconds: 350);
  static const Curve standardEasing = Curves.easeOutCubic;

  static Duration effective(BuildContext context, Duration duration) {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations ?? false ? Duration.zero : duration;
  }
}

enum KokoittaImageAspect {
  square(1),
  standard(4 / 3),
  wide(16 / 9);

  const KokoittaImageAspect(this.ratio);

  final double ratio;
}

/// Semantic colors that do not have a direct Material [ColorScheme] role.
///
/// Material roles such as primary, secondary, surface, outline, error, and
/// disabled control styling continue to come from [ColorScheme] and component
/// themes. These values cover product-specific status and map meanings only.
@immutable
class KokoittaSemanticColors
    extends ThemeExtension<KokoittaSemanticColors> {
  const KokoittaSemanticColors({
    required this.elevatedSurface,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.visited,
    required this.onVisited,
    required this.planned,
    required this.onPlanned,
    required this.unvisited,
    required this.onUnvisited,
    required this.destructive,
    required this.disabled,
    required this.focus,
  });

  final Color elevatedSurface;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color visited;
  final Color onVisited;
  final Color planned;
  final Color onPlanned;
  final Color unvisited;
  final Color onUnvisited;
  final Color destructive;
  final Color disabled;
  final Color focus;

  factory KokoittaSemanticColors.fromScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return KokoittaSemanticColors(
      elevatedSurface: isDark
          ? const Color(0xff1c2420)
          : const Color(0xffffffff),
      success: isDark ? const Color(0xff7fddb0) : const Color(0xff176b45),
      onSuccess: isDark ? const Color(0xff003822) : const Color(0xffffffff),
      successContainer: isDark
          ? const Color(0xff125235)
          : const Color(0xffc5f4db),
      onSuccessContainer: isDark
          ? const Color(0xffc5f4db)
          : const Color(0xff063d27),
      warning: isDark ? const Color(0xffffc66a) : const Color(0xff8a4f00),
      onWarning: isDark ? const Color(0xff4a2900) : const Color(0xffffffff),
      warningContainer: isDark
          ? const Color(0xff633c00)
          : const Color(0xffffddb0),
      onWarningContainer: isDark
          ? const Color(0xffffddb0)
          : const Color(0xff542f00),
      visited: isDark ? const Color(0xff77d5a2) : const Color(0xff1f7a4f),
      onVisited: isDark ? const Color(0xff003823) : const Color(0xffffffff),
      planned: isDark ? const Color(0xffffb39f) : const Color(0xffb23a20),
      onPlanned: isDark ? const Color(0xff5f1708) : const Color(0xffffffff),
      unvisited: isDark ? const Color(0xff68736c) : const Color(0xffd9dfda),
      onUnvisited: isDark ? const Color(0xffffffff) : const Color(0xff26312b),
      destructive: scheme.error,
      disabled: scheme.onSurface.withValues(alpha: 0.38),
      focus: isDark ? const Color(0xffffd166) : const Color(0xff754e00),
    );
  }

  @override
  KokoittaSemanticColors copyWith({
    Color? elevatedSurface,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? visited,
    Color? onVisited,
    Color? planned,
    Color? onPlanned,
    Color? unvisited,
    Color? onUnvisited,
    Color? destructive,
    Color? disabled,
    Color? focus,
  }) {
    return KokoittaSemanticColors(
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      visited: visited ?? this.visited,
      onVisited: onVisited ?? this.onVisited,
      planned: planned ?? this.planned,
      onPlanned: onPlanned ?? this.onPlanned,
      unvisited: unvisited ?? this.unvisited,
      onUnvisited: onUnvisited ?? this.onUnvisited,
      destructive: destructive ?? this.destructive,
      disabled: disabled ?? this.disabled,
      focus: focus ?? this.focus,
    );
  }

  @override
  KokoittaSemanticColors lerp(
    covariant KokoittaSemanticColors? other,
    double t,
  ) {
    if (other == null) return this;
    return KokoittaSemanticColors(
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      visited: Color.lerp(visited, other.visited, t)!,
      onVisited: Color.lerp(onVisited, other.onVisited, t)!,
      planned: Color.lerp(planned, other.planned, t)!,
      onPlanned: Color.lerp(onPlanned, other.onPlanned, t)!,
      unvisited: Color.lerp(unvisited, other.unvisited, t)!,
      onUnvisited: Color.lerp(onUnvisited, other.onUnvisited, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
    );
  }
}

extension KokoittaThemeContext on BuildContext {
  KokoittaSemanticColors get kokoittaColors {
    final colors = Theme.of(this).extension<KokoittaSemanticColors>();
    assert(colors != null, 'KokoittaSemanticColors is missing from ThemeData.');
    return colors!;
  }
}

ThemeData buildKokoittaDesignTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: isDark ? const Color(0xff8fd3aa) : const Color(0xff1b4332),
    brightness: brightness,
  ).copyWith(
    primary: isDark ? const Color(0xffb5e8c8) : const Color(0xff1b4332),
    secondary: isDark ? const Color(0xffffa58f) : const Color(0xffff7051),
    surface: isDark ? const Color(0xff121714) : const Color(0xfffcf9f8),
  );
  final semantic = KokoittaSemanticColors.fromScheme(scheme);
  final scaffold = scheme.surface;
  final navigation = isDark
      ? const Color(0xff18201c)
      : const Color(0xfff0eded);
  final baseTextTheme = ThemeData(
    brightness: brightness,
    useMaterial3: true,
  ).textTheme;
  final textTheme = baseTextTheme.copyWith(
    displaySmall: baseTextTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.12,
    ),
    headlineSmall: baseTextTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.2,
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w750,
      height: 1.25,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.5),
    bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.45),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    labelMedium: baseTextTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(KokoittaRadius.medium),
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    textTheme: textTheme,
    focusColor: semantic.focus,
    extensions: <ThemeExtension<dynamic>>[semantic],
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: semantic.elevatedSurface,
      elevation: 1,
      shadowColor: isDark ? Colors.black54 : const Color(0x221b4332),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KokoittaRadius.large),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: navigation,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(KokoittaSize.minimumTapTarget, KokoittaSize.minimumTapTarget),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(KokoittaSize.minimumTapTarget, KokoittaSize.minimumTapTarget),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(KokoittaSize.minimumTapTarget, KokoittaSize.minimumTapTarget),
        ),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KokoittaRadius.large),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KokoittaRadius.medium),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    useMaterial3: true,
  );
}
