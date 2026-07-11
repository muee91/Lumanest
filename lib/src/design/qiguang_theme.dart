import 'package:flutter/material.dart';

import 'qiguang_colors.dart';

/// Pre-built light and dark [ThemeData] for the Qiguang app.
abstract final class QiguangTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: QiguangColors.primaryLight,
          onPrimary: QiguangColors.onPrimaryLight,
          surface: QiguangColors.surfaceLight,
          onSurface: QiguangColors.onSurfaceLight,
          error: QiguangColors.safetyLight,
        ),
        scaffoldBackgroundColor: QiguangColors.backgroundLight,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: QiguangColors.primaryDark,
          onPrimary: QiguangColors.onPrimaryDark,
          surface: QiguangColors.surfaceDark,
          onSurface: QiguangColors.onSurfaceDark,
          error: QiguangColors.safetyDark,
        ),
        scaffoldBackgroundColor: QiguangColors.backgroundDark,
      );
}
