import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qiguang/src/design/qiguang_theme.dart';

void main() {
  group('QiguangTheme', () {
    test('light theme exposes readable color scheme', () {
      final theme = QiguangTheme.light;

      expect(theme.colorScheme, isNotNull);
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme exposes readable color scheme', () {
      final theme = QiguangTheme.dark;

      expect(theme.colorScheme, isNotNull);
      expect(theme.brightness, Brightness.dark);
    });

    test('primary foreground and background are distinct colors', () {
      final lightTheme = QiguangTheme.light;
      final darkTheme = QiguangTheme.dark;

      expect(
        lightTheme.colorScheme.primary,
        isNot(equals(lightTheme.colorScheme.onPrimary)),
      );
      expect(
        darkTheme.colorScheme.primary,
        isNot(equals(darkTheme.colorScheme.onPrimary)),
      );
    });

    test('light and dark themes produce different color schemes', () {
      final lightTheme = QiguangTheme.light;
      final darkTheme = QiguangTheme.dark;

      expect(lightTheme.colorScheme.primary, isNot(equals(darkTheme.colorScheme.primary)));
      expect(lightTheme.colorScheme.surface, isNot(equals(darkTheme.colorScheme.surface)));
    });
  });
}
