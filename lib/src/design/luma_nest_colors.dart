import 'package:flutter/material.dart';

/// Brand colour tokens for a quiet, daylight-first photography companion.
///
/// These are deliberately restrained base colours. The live environment palette
/// supplies atmosphere; static UI remains legible in direct sunlight.
abstract final class LumaNestColors {
  // ── Primary ──
  static const Color primaryLight = Color(0xFF285C55); // deep pine
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color primaryDark = Color(0xFF9AD7C8); // mineral mint
  static const Color onPrimaryDark = Color(0xFF102421);

  // ── Surface & background ──
  static const Color surfaceLight = Color(0xFFF9FBF9); // clouded daylight
  static const Color onSurfaceLight = Color(0xFF1D2B29);
  static const Color surfaceDark = Color(0xFF13201F);
  static const Color onSurfaceDark = Color(0xFFE6EFEC);

  static const Color backgroundLight = Color(0xFFEAF0EF); // mist and sky
  static const Color backgroundDark = Color(0xFF0C1514);

  // ── Accent ──
  static const Color accentLight = Color(0xFF356C88); // distant water
  static const Color accentDark = Color(0xFF82C5E7);

  // ── 山野胶片材质 ──
  static const Color paperLight = Color(0xFFF3E9D9);
  static const Color paperDark = Color(0xFF29251F);
  static const Color filmOrange = Color(0xFFD77A45);
  static const Color ridgeLight = Color(0xFF24574F);
  static const Color ridgeDark = Color(0xFF9AC7B4);
  static const Color skyWash = Color(0xFFAED1DE);
  static const Color rockGrey = Color(0xFF66716D);

  // ── Editorial support ──
  static const Color tertiaryLight = Color(0xFF5C6965);
  static const Color tertiaryDark = Color(0xFFB8C7C2);
  static const Color outlineLight = Color(0xFF778783);
  static const Color outlineDark = Color(0xFF81928E);

  // ── Safety / alert ──
  static const Color safetyLight = Color(0xFFB44343);
  static const Color safetyDark = Color(0xFFFFB4AC);

  // ── Ambient gradient stops ──
  static const Color ambientTopLight = Color(0xFFDDEBF0);
  static const Color ambientBottomLight = Color(0xFFF1F3E8);
  static const Color ambientTopDark = Color(0xFF19302F);
  static const Color ambientBottomDark = Color(0xFF0C1514);
}
