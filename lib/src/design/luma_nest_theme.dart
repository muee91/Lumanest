import 'package:flutter/material.dart';

import 'luma_nest_colors.dart';

/// Pre-built light and dark [ThemeData] for the LumaNest app.
abstract final class LumaNestTheme {
  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData get highContrastLight =>
      _build(Brightness.light, highContrast: true);

  static ThemeData get highContrastDark =>
      _build(Brightness.dark, highContrast: true);

  static ThemeData _build(Brightness brightness, {bool highContrast = false}) {
    final dark = brightness == Brightness.dark;
    final seed = dark
        ? LumaNestColors.primaryDark
        : LumaNestColors.primaryLight;
    var scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    if (!highContrast) {
      scheme = scheme.copyWith(
        primary: dark
            ? LumaNestColors.primaryDark
            : LumaNestColors.primaryLight,
        onPrimary: dark
            ? LumaNestColors.onPrimaryDark
            : LumaNestColors.onPrimaryLight,
        secondary: dark
            ? LumaNestColors.accentDark
            : LumaNestColors.accentLight,
        tertiary: dark
            ? LumaNestColors.tertiaryDark
            : LumaNestColors.tertiaryLight,
        surface: dark
            ? LumaNestColors.surfaceDark
            : LumaNestColors.surfaceLight,
        onSurface: dark
            ? LumaNestColors.onSurfaceDark
            : LumaNestColors.onSurfaceLight,
        outline: dark
            ? LumaNestColors.outlineDark
            : LumaNestColors.outlineLight,
        error: dark ? LumaNestColors.safetyDark : LumaNestColors.safetyLight,
      );
    }

    final typography = dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = typography.copyWith(
      displayLarge: typography.displayLarge?.copyWith(
        fontFamily: 'ZcoolXiaoWei',
        fontWeight: FontWeight.w700,
        letterSpacing: -1.6,
        height: 1.05,
      ),
      displayMedium: typography.displayMedium?.copyWith(
        fontFamily: 'ZcoolXiaoWei',
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.08,
      ),
      displaySmall: typography.displaySmall?.copyWith(
        fontFamily: 'ZcoolXiaoWei',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.12,
      ),
      headlineLarge: typography.headlineLarge?.copyWith(
        fontFamily: 'ZcoolXiaoWei',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.16,
      ),
      headlineMedium: typography.headlineMedium?.copyWith(
        fontFamily: 'ZcoolXiaoWei',
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
      ),
      headlineSmall: typography.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.28,
      ),
      titleLarge: typography.titleLarge?.copyWith(
        fontFamily: 'ZcoolXiaoWei',
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleMedium: typography.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: typography.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: typography.bodyMedium?.copyWith(height: 1.5),
      labelLarge: typography.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
    );
    final borderColor = scheme.outlineVariant.withValues(
      alpha: highContrast ? 1 : 0.72,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: dark
          ? LumaNestColors.backgroundDark
          : LumaNestColors.backgroundLight,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.headlineSmall?.copyWith(
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surface.withValues(alpha: 0.82),
        indicatorColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: selected ? 24 : 22,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.82),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor),
        ),
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelStyle: textTheme.labelMedium,
        selectedColor: scheme.secondaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 0.8,
        space: 24,
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 58,
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
        ),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
