import 'package:flutter/material.dart';

/// Hand-drawn glass bottle rendered via CustomPainter.
///
/// The bottle has a squat proportion (72% screen width x 280px),
/// a short wide neck, and a large rounded body. Glass material is
/// communicated through layered gradients, highlight stripes, and
/// wall-thickness outlines.
class BottleGlassPainter extends CustomPainter {
  BottleGlassPainter({
    required this.bottleScale,
    required this.ghostOpacity,
    required this.accentColor,
  });

  /// Scale factor: 1.0 at idle, 0.985 pressing, 0.97 lifting.
  final double bottleScale;

  /// Overall opacity: 1.0 normal, ~0.15 when slip is opened (ghost).
  final double ghostOpacity;

  /// Accent color for the neck ring (typically moss).
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Apply scale around center.
    if (bottleScale != 1.0) {
      canvas.translate(w / 2, h / 2);
      canvas.scale(bottleScale);
      canvas.translate(-w / 2, -h / 2);
    }

    final alpha = ghostOpacity.clamp(0.0, 1.0);

    // Bottle geometry.
    final neckWidth = w * 0.36;
    final neckHeight = h * 0.13;
    final neckTop = h * 0.02;
    final bodyTop = neckTop + neckHeight;
    final bodyWidth = w * 0.92;
    final bodyHeight = h - bodyTop - h * 0.03;
    final bodyLeft = (w - bodyWidth) / 2;
    final bodyRadius = bodyWidth * 0.22;
    final bottomRadius = bodyWidth * 0.34;

    // === Body path ===
    final bodyPath = Path()
      ..moveTo(bodyLeft + bodyRadius, bodyTop)
      // Top-left shoulder curve.
      ..cubicTo(
        bodyLeft, bodyTop,
        bodyLeft, bodyTop + bodyHeight * 0.12,
        bodyLeft, bodyTop + bodyHeight * 0.22,
      )
      // Left wall.
      ..lineTo(bodyLeft, bodyTop + bodyHeight * 0.72)
      // Bottom-left curve.
      ..cubicTo(
        bodyLeft, bodyTop + bodyHeight * 0.92,
        bodyLeft + bottomRadius * 0.6, bodyTop + bodyHeight,
        w / 2, bodyTop + bodyHeight,
      )
      // Bottom-right curve.
      ..cubicTo(
        bodyLeft + bodyWidth - bottomRadius * 0.6, bodyTop + bodyHeight,
        bodyLeft + bodyWidth, bodyTop + bodyHeight * 0.92,
        bodyLeft + bodyWidth, bodyTop + bodyHeight * 0.72,
      )
      // Right wall.
      ..lineTo(bodyLeft + bodyWidth, bodyTop + bodyHeight * 0.22)
      // Top-right shoulder curve.
      ..cubicTo(
        bodyLeft + bodyWidth, bodyTop + bodyHeight * 0.12,
        bodyLeft + bodyWidth, bodyTop,
        bodyLeft + bodyWidth - bodyRadius, bodyTop,
      )
      ..close();

    // === Glass fill gradient ===
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFAED1DE).withValues(alpha: 0.26 * alpha),
          const Color(0xFFAED1DE).withValues(alpha: 0.12 * alpha),
          const Color(0xFFF3E9D9).withValues(alpha: 0.10 * alpha),
        ],
      ).createShader(Rect.fromLTWH(bodyLeft, bodyTop, bodyWidth, bodyHeight));
    canvas.drawPath(bodyPath, fillPaint);

    // === Bottom warm refraction ===
    final bottomGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF3E9D9).withValues(alpha: 0.14 * alpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCenter(
        center: Offset(w / 2, bodyTop + bodyHeight * 0.88),
        width: bodyWidth * 0.7,
        height: bodyHeight * 0.3,
      ));
    canvas.drawPath(bodyPath, bottomGlow);

    // === Left highlight stripe (main refraction) ===
    final highlightLeft = bodyLeft + bodyWidth * 0.10;
    final highlightWidth = bodyWidth * 0.032;
    final highlightTop = bodyTop + bodyHeight * 0.10;
    final highlightBottom = bodyTop + bodyHeight * 0.78;
    final highlightRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(highlightLeft, highlightTop,
          highlightLeft + highlightWidth, highlightBottom),
      Radius.circular(highlightWidth / 2),
    );
    canvas.drawRRect(
      highlightRect,
      Paint()..color = Colors.white.withValues(alpha: 0.36 * alpha),
    );

    // === Right secondary highlight ===
    final highlight2Left = bodyLeft + bodyWidth * 0.82;
    final highlight2Width = bodyWidth * 0.018;
    final highlight2Rect = RRect.fromRectAndRadius(
      Rect.fromLTRB(highlight2Left, bodyTop + bodyHeight * 0.18,
          highlight2Left + highlight2Width, bodyTop + bodyHeight * 0.62),
      Radius.circular(highlight2Width / 2),
    );
    canvas.drawRRect(
      highlight2Rect,
      Paint()..color = Colors.white.withValues(alpha: 0.18 * alpha),
    );

    // === Wall outline (outer) ===
    final outerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.72 * alpha);
    canvas.drawPath(bodyPath, outerStroke);

    // === Wall outline (inner, thickness illusion) ===
    final innerPath = Path()
      ..moveTo(bodyLeft + bodyRadius + 2, bodyTop + 2)
      ..cubicTo(
        bodyLeft + 2, bodyTop + 2,
        bodyLeft + 2, bodyTop + bodyHeight * 0.12,
        bodyLeft + 2, bodyTop + bodyHeight * 0.22,
      )
      ..lineTo(bodyLeft + 2, bodyTop + bodyHeight * 0.72)
      ..cubicTo(
        bodyLeft + 2, bodyTop + bodyHeight * 0.91,
        bodyLeft + bottomRadius * 0.6, bodyTop + bodyHeight - 2,
        w / 2, bodyTop + bodyHeight - 2,
      )
      ..cubicTo(
        bodyLeft + bodyWidth - bottomRadius * 0.6, bodyTop + bodyHeight - 2,
        bodyLeft + bodyWidth - 2, bodyTop + bodyHeight * 0.91,
        bodyLeft + bodyWidth - 2, bodyTop + bodyHeight * 0.72,
      )
      ..lineTo(bodyLeft + bodyWidth - 2, bodyTop + bodyHeight * 0.22)
      ..cubicTo(
        bodyLeft + bodyWidth - 2, bodyTop + bodyHeight * 0.12,
        bodyLeft + bodyWidth - 2, bodyTop + 2,
        bodyLeft + bodyWidth - bodyRadius - 2, bodyTop + 2,
      )
      ..close();
    final innerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.28 * alpha);
    canvas.drawPath(innerPath, innerStroke);

    // === Neck ===
    final neckLeft = (w - neckWidth) / 2;
    final neckRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(neckLeft, neckTop, neckLeft + neckWidth, neckTop + neckHeight),
      const Radius.circular(12),
    );
    // Neck glass fill.
    canvas.drawRRect(
      neckRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.22 * alpha),
            const Color(0xFFAED1DE).withValues(alpha: 0.16 * alpha),
          ],
        ).createShader(neckRect.outerRect),
    );
    // Neck outline.
    canvas.drawRRect(
      neckRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.54 * alpha),
    );

    // === Neck ring (accent) ===
    final ringTop = neckTop + neckHeight * 0.32;
    final ringWidth = neckWidth * 1.18;
    final ringLeft = (w - ringWidth) / 2;
    final ringRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(ringLeft, ringTop, ringLeft + ringWidth, ringTop + 10),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      ringRect,
      Paint()..color = accentColor.withValues(alpha: 0.74 * alpha),
    );

    // === Neck highlight ===
    final neckHighlight = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        neckLeft + neckWidth * 0.14,
        neckTop + 4,
        neckLeft + neckWidth * 0.14 + 4,
        neckTop + neckHeight - 4,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      neckHighlight,
      Paint()..color = Colors.white.withValues(alpha: 0.30 * alpha),
    );
  }

  @override
  bool shouldRepaint(BottleGlassPainter oldDelegate) =>
      oldDelegate.bottleScale != bottleScale ||
      oldDelegate.ghostOpacity != ghostOpacity ||
      oldDelegate.accentColor != accentColor;
}
