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
      surface: LumaNestColors.surfaceDark,
      onSurface: LumaNestColors.onSurfaceDark,
      error: LumaNestColors.safetyDark,
    ),
    scaffoldBackgroundColor: LumaNestColors.backgroundDark,
  );
}
