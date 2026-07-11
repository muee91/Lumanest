import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
