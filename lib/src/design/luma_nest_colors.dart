import 'package:flutter/material.dart';

/// Brand colour tokens for a quiet, daylight-first photography companion.
///
/// These are deliberately restrained base colours. The live environment palette
/// supplies atmosphere; static UI remains legible in direct sunlight.
abstract final class LumaNestColors {
  // ── Primary ──
  // Pine is the instrument colour: it reads in direct sun, carries a quiet
  // outdoor character, and keeps the live sky/weather colours available for
  // the information layer.
  static const Color primaryLight = Color(0xFF2E6B5A);
  static const Color onPrimaryLight = Color(0xFFF8FBF7);
  static const Color primaryDark = Color(0xFF9BD1B7);
  static const Color onPrimaryDark = Color(0xFF102A22);

  // ── Surface & background ──
  static const Color surfaceLight = Color(0xFFF6F4ED);
  static const Color onSurfaceLight = Color(0xFF202923);
  static const Color surfaceDark = Color(0xFF121815);
  static const Color onSurfaceDark = Color(0xFFF1F5EF);

  static const Color backgroundLight = Color(0xFFF6F4ED);
  static const Color backgroundDark = Color(0xFF121815);

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
