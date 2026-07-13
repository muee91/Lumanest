import 'package:flutter/material.dart';

import 'luma_nest_colors.dart';

/// Pre-built light and dark [ThemeData] for the LumaNest app.
abstract final class LumaNestTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: LumaNestColors.primaryLight,
      onPrimary: LumaNestColors.onPrimaryLight,
      secondary: LumaNestColors.accentLight,
      surface: LumaNestColors.surfaceLight,
      onSurface: LumaNestColors.onSurfaceLight,
      error: LumaNestColors.safetyLight,
    ),
    scaffoldBackgroundColor: LumaNestColors.backgroundLight,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: LumaNestColors.primaryDark,
      onPrimary: LumaNestColors.onPrimaryDark,
      secondary: LumaNestColors.accentDark,
      surface: LumaNestColors.surfaceDark,
      onSurface: LumaNestColors.onSurfaceDark,
      error: LumaNestColors.safetyDark,
    ),
    scaffoldBackgroundColor: LumaNestColors.backgroundDark,
  );

  static ThemeData get highContrastLight => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: LumaNestColors.primaryLight,
      brightness: Brightness.light,
      contrastLevel: 1,
    ),
  );

  static ThemeData get highContrastDark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: LumaNestColors.primaryDark,
      brightness: Brightness.dark,
      contrastLevel: 1,
    ),
  );
}
