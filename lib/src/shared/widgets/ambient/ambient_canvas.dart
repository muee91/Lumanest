import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:luma_nest/src/design/luma_nest_colors.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

/// A static, non-interactive environment color layer.
///
/// Renders a low-motion layered gradient behind the app content.
/// When [palette] is provided, its colors replace the default
/// theme-based ambient stops. When [reduceMotion] is true the
/// canvas is completely static; otherwise a subtle animation
/// shifts the gradient stops.
///
/// The canvas does not intercept pointer events so interactive
/// content stacked on top remains fully functional.
class AmbientCanvas extends StatefulWidget {
  const AmbientCanvas({
    super.key,
    this.palette,
    this.visualState,
    this.reduceMotion = false,
    this.reduceFlashing = false,
    this.showWeatherTexture = true,
  });

  final AmbientPalette? palette;
  final AmbientVisualState? visualState;
  final bool reduceMotion;
  final bool reduceFlashing;
  final bool showWeatherTexture;

  @override
  State<AmbientCanvas> createState() => _AmbientCanvasState();
}

class _AmbientCanvasState extends State<AmbientCanvas>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curvedAnimation;

  void _startAnimation() {
    _stopAnimation();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat(reverse: true);
    _curvedAnimation = CurvedAnimation(
      parent: _controller!,
      curve: Curves.easeInOut,
    );
  }

  void _stopAnimation() {
    _controller?.stop();
    _curvedAnimation?.dispose();
    _controller?.dispose();
    _controller = null;
    _curvedAnimation = null;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _startAnimation();
    }
  }

  @override
  void didUpdateWidget(AmbientCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion == oldWidget.reduceMotion) return;

    if (widget.reduceMotion) {
      _stopAnimation();
    } else {
      _startAnimation();
    }
  }

  @override
  void dispose() {
    _stopAnimation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visualState = widget.visualState;
    final palette = visualState?.palette ?? widget.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topColor =
        palette?.topColor ??
        (isDark
            ? LumaNestColors.ambientTopDark
            : LumaNestColors.ambientTopLight);
    final bottomColor =
        palette?.bottomColor ??
        (isDark
            ? LumaNestColors.ambientBottomDark
            : LumaNestColors.ambientBottomLight);

    final direction = _flowAlignment(visualState?.flowDirection ?? 180);
    final motionIntensity = visualState?.motionIntensity ?? 0.16;
    Widget gradientLayer = _gradient(
      topColor,
      bottomColor,
      direction,
      motionOffset: 0,
    );

    if (_curvedAnimation != null) {
      gradientLayer = AnimatedBuilder(
        animation: _curvedAnimation!,
        builder: (_, child) {
          final t = _curvedAnimation!.value;
          return _gradient(
            topColor,
            bottomColor,
            direction,
            motionOffset: (t - .5) * motionIntensity,
          );
        },
      );
    }

    return SizedBox.expand(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            gradientLayer,
            if (widget.showWeatherTexture &&
                (visualState?.precipitationIntensity ?? 0) > 0)
              CustomPaint(
                painter: _PrecipitationTexturePainter(
                  intensity: visualState!.precipitationIntensity,
                  directionDegrees: visualState.flowDirection,
                  isSnow: false,
                ),
              ),
            if (widget.showWeatherTexture &&
                visualState?.thunderstorm == true &&
                !widget.reduceFlashing)
              _ThunderPulse(animation: _curvedAnimation),
          ],
        ),
      ),
    );
  }

  Alignment _flowAlignment(double degrees) {
    final radians = (degrees - 90) * math.pi / 180;
    return Alignment(math.cos(radians), math.sin(radians));
  }

  Widget _gradient(
    Color topColor,
    Color bottomColor,
    Alignment direction, {
    required double motionOffset,
  }) {
    final begin = Alignment(
      (direction.x + motionOffset).clamp(-1.0, 1.0),
      (direction.y + motionOffset).clamp(-1.0, 1.0),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: Alignment(-begin.x, -begin.y),
          colors: [
            topColor,
            Color.lerp(topColor, bottomColor, .52)!,
            bottomColor,
          ],
          stops: const [0, .52, 1],
        ),
      ),
    );
  }
}

class _PrecipitationTexturePainter extends CustomPainter {
  const _PrecipitationTexturePainter({
    required this.intensity,
    required this.directionDegrees,
    required this.isSnow,
  });

  final double intensity;
  final double directionDegrees;
  final bool isSnow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .05 + intensity * .1)
      ..strokeWidth = isSnow ? 2 : 1;
    final radians = directionDegrees * math.pi / 180;
    final slant = math.sin(radians) * (8 + intensity * 22);
    final length = 12 + intensity * 34;
    final spacing = (42 - intensity * 24).clamp(16, 42);
    for (var x = -length; x < size.width + length; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing * 1.6) {
        canvas.drawLine(Offset(x, y), Offset(x + slant, y + length), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PrecipitationTexturePainter oldDelegate) =>
      oldDelegate.intensity != intensity ||
      oldDelegate.directionDegrees != directionDegrees ||
      oldDelegate.isSnow != isSnow;
}

class _ThunderPulse extends StatelessWidget {
  const _ThunderPulse({required this.animation});

  final Animation<double>? animation;

  @override
  Widget build(BuildContext context) {
    if (animation == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: animation!,
      builder: (_, _) {
        final nearPeak = (animation!.value - .92).abs() < .018;
        return ColoredBox(
          color: Colors.white.withValues(alpha: nearPeak ? .06 : 0),
        );
      },
    );
  }
}
