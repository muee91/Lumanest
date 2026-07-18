import 'package:flutter/material.dart';

import 'luma_nest_colors.dart';

/// The restrained visual language for a photography instrument. Atmosphere is
/// supplied by the ambient canvas; application surfaces stay quiet and legible.
abstract final class LumaNestTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get highContrastLight =>
      _build(Brightness.light, highContrast: true);
  static ThemeData get highContrastDark =>
      _build(Brightness.dark, highContrast: true);

  static ThemeData _build(Brightness brightness, {bool highContrast = false}) {
    final dark = brightness == Brightness.dark;
    final scheme = _scheme(dark: dark, highContrast: highContrast);
    final typography = dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = typography.copyWith(
      // Page titles and body copy use the system sans-serif face. The brand
      // face (ZcoolXiaoWei) is reserved for brand and paper-note surfaces via
      // LumaNestTextStyles; it is never applied to titles or running text.
      displayLarge: typography.displayLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.4,
        height: 1.08,
      ),
      displayMedium: typography.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.1,
      ),
      displaySmall: typography.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.6,
        height: 1.14,
      ),
      headlineLarge: typography.headlineLarge?.copyWith(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -.4,
        height: 1.18,
      ),
      headlineMedium: typography.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.22,
      ),
      headlineSmall: typography.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.28,
      ),
      titleLarge: typography.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      titleMedium: typography.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodyLarge: typography.bodyLarge?.copyWith(fontSize: 15, height: 1.55),
      bodyMedium: typography.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      bodySmall: typography.bodySmall?.copyWith(fontSize: 13, height: 1.45),
      labelSmall: typography.labelSmall?.copyWith(fontSize: 12),
      labelLarge: typography.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: .12,
      ),
    );
    final borderColor = scheme.outlineVariant.withValues(
      alpha: highContrast ? 1 : .56,
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
      splashFactory: NoSplash.splashFactory,
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
        color: scheme.surfaceContainerLow.withValues(alpha: .94),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaNestRadii.card),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
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
            size: 23,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumaNestRadii.button),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumaNestRadii.button),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumaNestRadii.button),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh.withValues(alpha: .84),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(LumaNestRadii.input),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(LumaNestRadii.input),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(LumaNestRadii.input),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaNestRadii.label),
        ),
        side: BorderSide(color: borderColor),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        labelStyle: textTheme.labelMedium,
        selectedColor: scheme.secondaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: .8,
        space: 24,
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 58,
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaNestRadii.card),
        ),
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumaNestRadii.sheetTop),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaNestRadii.primaryContainer),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaNestRadii.button),
        ),
      ),
    );
  }

  static ColorScheme _scheme({required bool dark, required bool highContrast}) {
    final primary = highContrast
        ? (dark ? const Color(0xFFC7F5E6) : const Color(0xFF103E37))
        : (dark ? LumaNestColors.primaryDark : LumaNestColors.primaryLight);
    final onPrimary = highContrast
        ? (dark ? const Color(0xFF071714) : Colors.white)
        : (dark ? LumaNestColors.onPrimaryDark : LumaNestColors.onPrimaryLight);
    final surface = dark
        ? LumaNestColors.surfaceDark
        : LumaNestColors.surfaceLight;
    final onSurface = dark
        ? LumaNestColors.onSurfaceDark
        : LumaNestColors.onSurfaceLight;
    final muted = dark ? const Color(0xFF1B2522) : const Color(0xFFECEBE5);
    final secondary = dark
        ? LumaNestColors.accentDark
        : LumaNestColors.accentLight;
    final tertiary = dark ? LumaNestColors.warmDark : LumaNestColors.warmLight;
    return ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: dark
          ? const Color(0xFF214C44)
          : const Color(0xFFD5E8E0),
      onPrimaryContainer: dark
          ? const Color(0xFFC0E9DA)
          : const Color(0xFF153D36),
      secondary: secondary,
      onSecondary: dark ? const Color(0xFF07354B) : Colors.white,
      secondaryContainer: dark
          ? const Color(0xFF234B5D)
          : const Color(0xFFD5E9F3),
      onSecondaryContainer: dark
          ? const Color(0xFFC5E8FA)
          : const Color(0xFF193E4F),
      tertiary: tertiary,
      onTertiary: dark ? const Color(0xFF29312E) : Colors.white,
      tertiaryContainer: dark
          ? const Color(0xFF3B4541)
          : const Color(0xFFE1E7E2),
      onTertiaryContainer: dark
          ? const Color(0xFFD7E1DB)
          : const Color(0xFF303B36),
      error: dark ? LumaNestColors.safetyDark : LumaNestColors.safetyLight,
      onError: dark ? const Color(0xFF690008) : Colors.white,
      errorContainer: dark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
      onErrorContainer: dark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410002),
      surface: surface,
      onSurface: onSurface,
      surfaceDim: muted,
      surfaceBright: dark ? const Color(0xFF222D29) : Colors.white,
      surfaceContainerLowest: dark ? const Color(0xFF0E1513) : Colors.white,
      surfaceContainerLow: muted,
      surfaceContainer: dark
          ? const Color(0xFF202A26)
          : const Color(0xFFF1F0EA),
      surfaceContainerHigh: dark
          ? const Color(0xFF28322E)
          : const Color(0xFFE9E8E1),
      surfaceContainerHighest: dark
          ? const Color(0xFF303B36)
          : const Color(0xFFE2E2DB),
      onSurfaceVariant: dark
          ? const Color(0xFFB6C0C7)
          : const Color(0xFF626B73),
      outline: dark ? LumaNestColors.outlineDark : LumaNestColors.outlineLight,
      outlineVariant: dark ? const Color(0xFF414D48) : const Color(0xFFC4CCC6),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? const Color(0xFFE7ECE7) : const Color(0xFF2A3430),
      onInverseSurface: dark
          ? const Color(0xFF1A211E)
          : const Color(0xFFF3F7F2),
      inversePrimary: dark
          ? LumaNestColors.primaryLight
          : LumaNestColors.primaryDark,
      surfaceTint: primary,
    );
  }
}
