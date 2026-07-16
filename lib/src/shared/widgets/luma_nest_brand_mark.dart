import 'package:flutter/material.dart';

/// Compact ridge-and-first-light mark shared by in-app brand surfaces.
class LumaNestBrandMark extends StatelessWidget {
  const LumaNestBrandMark({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _LumaNestBrandMarkPainter()),
  );
}

class _LumaNestBrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 30;
    final sun = Paint()..color = const Color(0xFFD77A45);
    final ridge = Paint()
      ..color = const Color(0xFF24574F)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.2 * scale;
    final water = Paint()
      ..color = const Color(0xFF356C88)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8 * scale;
    canvas.drawCircle(Offset(20.5 * scale, 8.5 * scale), 4.1 * scale, sun);
    final mountain = Path()
      ..moveTo(4 * scale, 23 * scale)
      ..lineTo(13.4 * scale, 15.6 * scale)
      ..lineTo(20.8 * scale, 10.2 * scale)
      ..lineTo(26 * scale, 7 * scale);
    canvas.drawPath(mountain, ridge);
    canvas.drawLine(
      Offset(5.2 * scale, 25.2 * scale),
      Offset(25.5 * scale, 21.7 * scale),
      water,
    );
  }

  @override
  bool shouldRepaint(covariant _LumaNestBrandMarkPainter oldDelegate) => false;
}
