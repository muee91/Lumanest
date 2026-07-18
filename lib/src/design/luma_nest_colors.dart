import 'package:flutter/material.dart';

/// Brand colour tokens for a quiet, daylight-first photography companion.
///
/// These are deliberately restrained base colours. The live environment palette
/// supplies atmosphere; static UI remains legible in direct sunlight.
abstract final class LumaNestColors {
  // ── Primary ──
  static const Color primaryLight = Color(0xFF00A5E9);
  static const Color onPrimaryLight = Color(0xFF061E29);
  static const Color primaryDark = Color(0xFF37B5EA);
  static const Color onPrimaryDark = Color(0xFF061E29);

  // ── Surface & background ──
  static const Color surfaceLight = Color(0xFFF6F6F5);
  static const Color onSurfaceLight = Color(0xFF25292D);
  static const Color surfaceDark = Color(0xFF12161A);
  static const Color onSurfaceDark = Color(0xFFF5F7F8);

  static const Color backgroundLight = Color(0xFFF6F6F5);
  static const Color backgroundDark = Color(0xFF12161A);

  // ── Accent ──
  static const Color accentLight = Color(0xFF91A86B);
  static const Color accentDark = Color(0xFFA6BB7D);
  static const Color warmLight = Color(0xFFFF8754);
  static const Color warmDark = Color(0xFFFF956A);

  // ── 山野胶片材质 ──
  static const Color paperLight = Color(0xFFF3E9D9);
  static const Color paperDark = Color(0xFF29251F);
  static const Color filmOrange = Color(0xFFD77A45);
  static const Color ridgeLight = Color(0xFF24574F);
  static const Color ridgeDark = Color(0xFF9AC7B4);
  static const Color skyWash = Color(0xFFAED1DE);
  static const Color rockGrey = Color(0xFF66716D);

  // ── Editorial support ──
  static const Color tertiaryLight = Color(0xFF8B949C);
  static const Color tertiaryDark = Color(0xFF86919A);
  static const Color outlineLight = Color(0xFF8B949C);
  static const Color outlineDark = Color(0xFF86919A);

  // ── Safety / alert ──
  static const Color safetyLight = Color(0xFFED6C72);
  static const Color safetyDark = Color(0xFFFF858A);

  // ── Ambient gradient stops ──
  static const Color ambientTopLight = Color(0xFFDDEBF0);
  static const Color ambientBottomLight = Color(0xFFF1F3E8);
  static const Color ambientTopDark = Color(0xFF19302F);
  static const Color ambientBottomDark = Color(0xFF0C1514);
}

/// Shared geometry keeps the app calm and editorial instead of card-heavy.
/// Three tiers: compact controls, regular content, expansive sheets/navigation.
abstract final class LumaNestRadii {
  static const double label = 12;
  static const double icon = 14;
  static const double input = 16;
  static const double button = 18;
  static const double card = 22;
  static const double navigation = 24;
  static const double primaryContainer = 28;
  static const double sheetTop = 30;

  static const double compact = button;
  static const double regular = card;
  static const double expansive = primaryContainer;
}
