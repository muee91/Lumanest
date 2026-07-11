import 'package:flutter/material.dart';
import 'package:luma_nest/src/design/luma_nest_colors.dart';

/// A static, non-interactive environment color layer.
///
/// Renders a low-motion layered gradient behind the app content.
/// When [reduceMotion] is true the canvas is completely static;
/// otherwise a subtle animation shifts the gradient stops.
///
/// The canvas does not intercept pointer events so interactive
/// content stacked on top remains fully functional.
class AmbientCanvas extends StatefulWidget {
  const AmbientCanvas({
    super.key,
    this.reduceMotion = false,
    this.reduceFlashing = false,
  });

  final bool reduceMotion;
  final bool reduceFlashing;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topColor = isDark
        ? LumaNestColors.ambientTopDark
        : LumaNestColors.ambientTopLight;
    final bottomColor = isDark
        ? LumaNestColors.ambientBottomDark
        : LumaNestColors.ambientBottomLight;

    Widget gradientLayer = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
      ),
    );

    if (_curvedAnimation != null) {
      gradientLayer = AnimatedBuilder(
        animation: _curvedAnimation!,
        builder: (_, child) {
          final t = _curvedAnimation!.value;
          final range = widget.reduceFlashing ? 0.1 : 0.4;
          final start = widget.reduceFlashing ? 0.45 : 0.3;
          final midColor = Color.lerp(
            topColor,
            bottomColor,
            start + t * range,
          )!;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [topColor, midColor, bottomColor],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          );
        },
      );
    }

    return SizedBox.expand(child: IgnorePointer(child: gradientLayer));
  }
}
