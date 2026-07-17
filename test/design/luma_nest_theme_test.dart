import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/design/luma_nest_colors.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';

/// WCAG 2.1 relative luminance.
double _relativeLuminance(Color color) {
  double linearize(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}

/// WCAG 2.1 contrast ratio.
double _contrastRatio(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('LumaNestTheme', () {
    test('light theme exposes readable color scheme', () {
      final theme = LumaNestTheme.light;

      expect(theme.colorScheme, isNotNull);
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme exposes readable color scheme', () {
      final theme = LumaNestTheme.dark;

      expect(theme.colorScheme, isNotNull);
      expect(theme.brightness, Brightness.dark);
    });

    test('light and dark themes produce different color schemes', () {
      final lightTheme = LumaNestTheme.light;
      final darkTheme = LumaNestTheme.dark;

      expect(
        lightTheme.colorScheme.primary,
        isNot(equals(darkTheme.colorScheme.primary)),
      );
      expect(
        lightTheme.colorScheme.surface,
        isNot(equals(darkTheme.colorScheme.surface)),
      );
    });

    test('maps the LumaNest accent tokens to secondary colors', () {
      expect(
        LumaNestTheme.light.colorScheme.secondary,
        LumaNestColors.accentLight,
      );
      expect(
        LumaNestTheme.dark.colorScheme.secondary,
        LumaNestColors.accentDark,
      );
    });

    test('applies the shared daylight component language', () {
      final theme = LumaNestTheme.light;

      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.navigationBarTheme.height, 68);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.textTheme.displaySmall?.fontWeight, FontWeight.w700);
    });

    test('keeps page titles and body copy on the system sans-serif face', () {
      final theme = LumaNestTheme.dark;

      // The brand face (ZcoolXiaoWei) must not leak into titles or body copy;
      // they stay on the platform sans-serif (e.g. Roboto).
      for (final style in [
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.displaySmall,
        theme.textTheme.headlineLarge,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
      ]) {
        expect(
          style?.fontFamily,
          isNot('ZcoolXiaoWei'),
          reason: 'titles must stay on the sans-serif face',
        );
      }
    });

    test('uses the three-tier radii tokens', () {
      expect(LumaNestRadii.compact, 8);
      expect(LumaNestRadii.regular, 16);
      expect(LumaNestRadii.expansive, 28);

      final theme = LumaNestTheme.light;
      // Buttons and inputs use the compact tier.
      expect(
        (theme.filledButtonTheme.style!.shape!.resolve({})!
                as RoundedRectangleBorder)
            .borderRadius
            .resolve(TextDirection.ltr)
            .topLeft
            .x,
        LumaNestRadii.compact,
      );
      // Cards use the regular tier.
      expect(
        (theme.cardTheme.shape as RoundedRectangleBorder).borderRadius
            .resolve(TextDirection.ltr)
            .topLeft
            .x,
        LumaNestRadii.regular,
      );
      // Sheets use the expansive tier.
      expect(
        (theme.bottomSheetTheme.shape as RoundedRectangleBorder).borderRadius
            .resolve(TextDirection.ltr)
            .topLeft
            .x,
        LumaNestRadii.expansive,
      );
    });

    test('high contrast themes increase primary contrast', () {
      final normalLight = _contrastRatio(
        LumaNestTheme.light.colorScheme.primary,
        LumaNestTheme.light.colorScheme.onPrimary,
      );
      final contrastLight = _contrastRatio(
        LumaNestTheme.highContrastLight.colorScheme.primary,
        LumaNestTheme.highContrastLight.colorScheme.onPrimary,
      );
      final normalDark = _contrastRatio(
        LumaNestTheme.dark.colorScheme.primary,
        LumaNestTheme.dark.colorScheme.onPrimary,
      );
      final contrastDark = _contrastRatio(
        LumaNestTheme.highContrastDark.colorScheme.primary,
        LumaNestTheme.highContrastDark.colorScheme.onPrimary,
      );

      expect(contrastLight, greaterThan(normalLight));
      expect(contrastDark, greaterThan(normalDark));
      expect(contrastLight, greaterThanOrEqualTo(7));
      expect(contrastDark, greaterThanOrEqualTo(7));
    });

    group('WCAG contrast', () {
      test('light primary/onPrimary contrast ≥ 4.5:1', () {
        final theme = LumaNestTheme.light;
        final ratio = _contrastRatio(
          theme.colorScheme.primary,
          theme.colorScheme.onPrimary,
        );
        expect(ratio, greaterThanOrEqualTo(4.5));
      });

      test('dark primary/onPrimary contrast ≥ 4.5:1', () {
        final theme = LumaNestTheme.dark;
        final ratio = _contrastRatio(
          theme.colorScheme.primary,
          theme.colorScheme.onPrimary,
        );
        expect(ratio, greaterThanOrEqualTo(4.5));
      });
    });
  });
}
