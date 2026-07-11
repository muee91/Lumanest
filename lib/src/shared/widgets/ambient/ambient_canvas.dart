import 'package:flutter/material.dart';

import '../../../design/qiguang_colors.dart';

/// A static, non-interactive environment color layer.
///
/// Renders a low-motion layered gradient behind the app content.
/// When [reduceMotion] is true the canvas is completely static;
/// otherwise a subtle animation shifts the gradient stops.
///
/// The canvas does not intercept pointer events so interactive
/// content stacked on top remains fully functional.
class AmbientCanvas extends StatefulWidget {
  const AmbientCanvas({super.key, this.reduceMotion = false});

  final bool reduceMotion;

  @override
  State<AmbientCanvas> createState() => _AmbientCanvasState();
}

class _AmbientCanvasState extends State<AmbientCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController? _controller;
  late final Animation<double>? _animation;

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _controller = null;
      _animation = null;
    } else {
      _controller = AnimationController(
        duration: const Duration(seconds: 20),
        vsync: this,
      )..repeat(reverse: true);
      _animation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topColor = isDark
        ? QiguangColors.ambientTopDark
        : QiguangColors.ambientTopLight;
    final bottomColor = isDark
        ? QiguangColors.ambientBottomDark
        : QiguangColors.ambientBottomLight;

    Widget gradientLayer = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
      ),
    );

    if (_animation != null) {
      gradientLayer = AnimatedBuilder(
        animation: _animation,
        builder: (_, child) {
          final t = _animation.value;
          final midColor = Color.lerp(topColor, bottomColor, 0.3 + t * 0.4)!;
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

    return SizedBox.expand(
      child: IgnorePointer(
        child: gradientLayer,
      ),
    );
  }
}
