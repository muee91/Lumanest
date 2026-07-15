import 'package:flutter/material.dart';

/// Brand color tokens for the LumaNest design system.
///
/// Warm, earthy tones inspired by natural light and photography.
abstract final class LumaNestColors {
  // ── Primary ──
  static const Color primaryLight = Color(0xFF8B6914); // dark goldenrod
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color primaryDark = Color(0xFFDAA520); // goldenrod
  static const Color onPrimaryDark = Color(0xFF1A1A2E);

  // ── Surface & background ──
  static const Color surfaceLight = Color(0xFFFDFBF7); // warm cream
  static const Color onSurfaceLight = Color(0xFF2D2D2D);
  static const Color surfaceDark = Color(0xFF1A1A2E);
  static const Color onSurfaceDark = Color(0xFFE8E4DD);

  static const Color backgroundLight = Color(0xFFF5F0E8); // warm parchment
  static const Color backgroundDark = Color(0xFF0F0F1A);

  // ── Accent ──
  static const Color accentLight = Color(0xFF5B8C5A); // muted sage
  static const Color accentDark = Color(0xFF7CB77C);

  // ── Editorial support ──
  static const Color tertiaryLight = Color(0xFF6E665D);
  static const Color tertiaryDark = Color(0xFFB9AFA3);
  static const Color outlineLight = Color(0xFF8C8378);
  static const Color outlineDark = Color(0xFF90887E);

  // ── Safety / alert ──
  static const Color safetyLight = Color(0xFFC75050);
  static const Color safetyDark = Color(0xFFE07070);

  // ── Ambient gradient stops ──
  static const Color ambientTopLight = Color(0xFFF0E6D3);
  static const Color ambientBottomLight = Color(0xFFE8DCC8);
  static const Color ambientTopDark = Color(0xFF1A1A2E);
  static const Color ambientBottomDark = Color(0xFF0F0F1A);
}
