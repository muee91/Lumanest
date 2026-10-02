import 'package:flutter/material.dart';

abstract final class V2Palette {
  static const canvas = Color(0xFFF5F5F1);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF171A18);
  static const mutedInk = Color(0xFF6E736D);
  static const line = Color(0xFFD9DDD4);
  static const moss = Color(0xFF819D4B);
  static const mossSoft = Color(0xFFE7EED9);
  static const sky = Color(0xFF2AADE2);
  static const skySoft = Color(0xFFDDF2FA);
  static const ember = Color(0xFFFF8050);
  static const emberSoft = Color(0xFFFFE8DE);
  static const night = Color(0xFF17201D);
  static const danger = Color(0xFFE55D67);
  static const dangerSoft = Color(0xFFFFE7E8);
}

/// Maps the original V2 palette roles onto the active Material color scheme.
///
/// V2 screens still use the named palette roles heavily, so keeping this
/// mapping in one place lets light, dark, and high-contrast themes share the
/// same visual language without duplicating per-page color branches.
extension V2ThemePalette on BuildContext {
  Color get v2Canvas => Theme.of(this).colorScheme.surface;

  Color get v2Paper => Theme.of(this).colorScheme.surfaceContainerLow;

  Color get v2Ink => Theme.of(this).colorScheme.onSurface;

  Color get v2MutedInk => Theme.of(this).colorScheme.onSurfaceVariant;

  Color get v2Line => Theme.of(this).colorScheme.outlineVariant;

  Color get v2Moss => Theme.of(this).colorScheme.primary;

  Color get v2MossSoft => Theme.of(this).colorScheme.primaryContainer;

  Color get v2Sky => Theme.of(this).colorScheme.secondary;

  Color get v2SkySoft => Theme.of(this).colorScheme.secondaryContainer;

  Color get v2Ember => Theme.of(this).colorScheme.tertiary;

  Color get v2EmberSoft => Theme.of(this).colorScheme.tertiaryContainer;

  Color get v2Night => Theme.of(this).colorScheme.surfaceContainerLowest;

  Color get v2Danger => Theme.of(this).colorScheme.error;

  Color get v2DangerSoft => Theme.of(this).colorScheme.errorContainer;
}

abstract final class V2Geometry {
  static const page = 22.0;
  static const object = 34.0;
  static const control = 22.0;
  static const compact = 16.0;
  static const nav = 28.0;
}
