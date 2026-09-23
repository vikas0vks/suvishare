import 'package:flutter/material.dart';

/// Suvi Share design tokens (see docs/02-research-ux-design.md §2).
class SuviColors {
  SuviColors._();
  static const Color suviTeal = Color(0xFF00897B);
  static const Color signalAmber = Color(0xFFFFB300);
  static const Color lotusPink = Color(0xFFD81B60);

  /// 8-step avatar hue ring.
  static const List<Color> avatarPalette = [
    Color(0xFF00897B), // teal
    Color(0xFF3949AB), // indigo
    Color(0xFFD81B60), // pink
    Color(0xFFF4511E), // deep orange
    Color(0xFF8E24AA), // purple
    Color(0xFF039BE5), // light blue
    Color(0xFF43A047), // green
    Color(0xFFFB8C00), // orange
  ];

  static Color avatar(int index) => avatarPalette[index % avatarPalette.length];
}

/// Persisted color personalities. Brightness is controlled separately through
/// [ThemeMode], so every palette works in light, dark, and system mode.
enum AppPalette { suvi, ocean, sunset, forest, lavender, rose }

extension AppPaletteColors on AppPalette {
  Color get seed => switch (this) {
    AppPalette.suvi => const Color(0xFF00897B),
    AppPalette.ocean => const Color(0xFF1565C0),
    AppPalette.sunset => const Color(0xFFE64A3B),
    AppPalette.forest => const Color(0xFF2E7D57),
    AppPalette.lavender => const Color(0xFF7656C8),
    AppPalette.rose => const Color(0xFFC83E73),
  };

  Color get accent => switch (this) {
    AppPalette.suvi => const Color(0xFFFFB300),
    AppPalette.ocean => const Color(0xFF00ACC1),
    AppPalette.sunset => const Color(0xFFFFA000),
    AppPalette.forest => const Color(0xFF8AAE42),
    AppPalette.lavender => const Color(0xFFB65FCF),
    AppPalette.rose => const Color(0xFFF06292),
  };
}

class SuviSpacing {
  SuviSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class SuviRadius {
  SuviRadius._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 28;
}

class SuviMotion {
  SuviMotion._();
  static const Duration short = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 500);
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve decelerate = Curves.easeOutCubic;
}

/// Window size classes (Material 3).
enum WindowClass { compact, medium, expanded }

WindowClass windowClassOf(double width) {
  if (width < 600) return WindowClass.compact;
  if (width < 840) return WindowClass.medium;
  return WindowClass.expanded;
}

class SuviTheme {
  SuviTheme._();

  static ThemeData light(
    ColorScheme? dynamic, {
    AppPalette palette = AppPalette.suvi,
  }) => _build(
    dynamic ?? colorScheme(palette, Brightness.light),
    Brightness.light,
  );

  static ThemeData dark(
    ColorScheme? dynamic, {
    AppPalette palette = AppPalette.suvi,
  }) =>
      _build(dynamic ?? colorScheme(palette, Brightness.dark), Brightness.dark);

  static ColorScheme colorScheme(AppPalette palette, Brightness brightness) =>
      ColorScheme.fromSeed(seedColor: palette.seed, brightness: brightness);

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: 'Inter',
      fontFamilyFallback: const [
        'NotoSansDevanagari',
        'Segoe UI',
        'Roboto',
        'sans-serif',
      ],
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;
    TextStyle heading(TextStyle? s, {FontWeight w = FontWeight.w700}) =>
        (s ?? const TextStyle()).copyWith(
          fontFamily: 'Manrope',
          fontWeight: w,
          letterSpacing: -0.2,
          fontFamilyFallback: const [
            'NotoSansDevanagari',
            'Segoe UI',
            'Roboto',
          ],
        );
    final textTheme = text.copyWith(
      displayLarge: heading(text.displayLarge, w: FontWeight.w800),
      displayMedium: heading(text.displayMedium, w: FontWeight.w800),
      displaySmall: heading(text.displaySmall),
      headlineLarge: heading(text.headlineLarge),
      headlineMedium: heading(text.headlineMedium),
      headlineSmall: heading(text.headlineSmall),
      titleLarge: heading(text.titleLarge, w: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: Color.alphaBlend(
        scheme.primary.withValues(
          alpha: brightness == Brightness.dark ? 0.035 : 0.018,
        ),
        scheme.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SuviRadius.lg),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SuviRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SuviSpacing.lg,
          vertical: SuviSpacing.xs,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: SuviSpacing.xl),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: SuviSpacing.xl),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: const StadiumBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SuviRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SuviRadius.md),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SuviSpacing.lg,
          vertical: SuviSpacing.md,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SuviRadius.xl),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SuviRadius.xl),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SuviRadius.md),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelType: NavigationRailLabelType.all,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerLow,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SuviRadius.md),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
