import 'package:flutter/material.dart';

/// Brand typography tokens.
///
/// The system sans-serif face (configured on the theme) is used for page
/// titles and body copy. The Zcool XiaoWei face is reserved for brand
/// statements and paper-note (纸条) surfaces so the brand voice stays
/// distinctive without compromising the readability of running text or the
/// ambient background.
abstract final class LumaNestTextStyles {
  static const String brandFamily = 'ZcoolXiaoWei';

  /// Brand display face for hero statements and brand surfaces.
  ///
  /// Uses the natural Regular weight of the XiaoWei face to avoid synthetic
  /// bold at large sizes. Pair with [LumaNestSurfaceTone.paper] or place
  /// directly over the ambient background.
  static TextStyle brand({
    Color? color,
    double fontSize = 28,
    double letterSpacing = -0.4,
  }) => TextStyle(
    fontFamily: brandFamily,
    fontWeight: FontWeight.w400,
    fontSize: fontSize,
    height: 1.18,
    letterSpacing: letterSpacing,
    color: color,
  );

  /// Compact brand label, e.g. the brand eyebrow next to the brand mark.
  static TextStyle brandLabel({Color? color, double fontSize = 13}) =>
      TextStyle(
        fontFamily: brandFamily,
        fontWeight: FontWeight.w400,
        fontSize: fontSize,
        height: 1.35,
        letterSpacing: 0.3,
        color: color,
      );

  /// Paper-note face for 纸条 and editorial paper surfaces.
  static TextStyle paperNote({Color? color, double fontSize = 16}) => TextStyle(
    fontFamily: brandFamily,
    fontWeight: FontWeight.w400,
    fontSize: fontSize,
    height: 1.55,
    color: color,
  );
}
