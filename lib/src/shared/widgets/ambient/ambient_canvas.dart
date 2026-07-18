import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/design/luma_nest_colors.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_rendering_policy.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_shader_surface.dart';
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
    this.renderer = AmbientRenderer.fragment,
    this.intensity = 1.0,
    this.interactionSuppressed,
  });

  final AmbientPalette? palette;
  final AmbientVisualState? visualState;
  final bool reduceMotion;
  final bool reduceFlashing;
  final bool showWeatherTexture;
  final AmbientRenderer renderer;

  /// Page-level ambient strength (0.0 = static, 1.0 = full).
  final double intensity;

  /// Optional externally-driven flag that becomes true while the user is
  /// scrolling or otherwise interacting, so the canvas can dampen motion per
  /// design §9.3. The canvas listens to this and rebuilds on change.
  final ValueListenable<bool>? interactionSuppressed;

  @override
  State<AmbientCanvas> createState() => _AmbientCanvasState();
}

class _AmbientCanvasState extends State<AmbientCanvas>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curvedAnimation;

  // Gust-driven occasional disturbance (design §9.1: 阵风决定偶发扰动).
  AnimationController? _gustController;
  Timer? _gustTimer;
  late final math.Random _gustRandom;

  AnimationController? _thunderController;
  Timer? _thunderTimer;
  late final math.Random _thunderRandom;

  bool get _shouldAnimate => !widget.reduceMotion && widget.intensity > 0;

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

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (_controller == null) _startAnimation();
    } else {
      _stopAnimation();
    }
  }

  /// Schedules the next gust pulse. Higher gust factors shorten the interval
  /// toward the 3–8 second band; the pulse itself is a brief forward/reverse
  /// spike layered on top of the steady wind motion.
  void _ensureGust() {
    final gustFactor = widget.visualState?.gustFactor ?? 0;
    final shouldGust = _shouldAnimate && gustFactor > 0;
    if (!shouldGust) {
      _stopGust();
      return;
    }
    _gustController ??=
        AnimationController(
          duration: const Duration(milliseconds: 700),
          vsync: this,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _gustController?.reverse();
          }
        });
    _scheduleNextGust(gustFactor);
  }

  void _scheduleNextGust(double gustFactor) {
    _gustTimer?.cancel();
    const minMs = 3000;
    const maxMs = 8000;
    final span = (maxMs - minMs) * (1 - gustFactor.clamp(0.0, 1.0));
    final delay = minMs + span + _gustRandom.nextDouble() * 800;
    _gustTimer = Timer(Duration(milliseconds: delay.round()), () {
      if (!mounted) return;
      if (_shouldAnimate) {
        _gustController?.forward();
      }
      _scheduleNextGust(gustFactor);
    });
  }

  void _stopGust() {
    _gustTimer?.cancel();
    _gustTimer = null;
    _gustController?.stop();
    _gustController?.dispose();
    _gustController = null;
  }

  bool get _shouldThunder =>
      _shouldAnimate &&
      !widget.reduceFlashing &&
      widget.visualState?.thunderstorm == true;

  void _ensureThunder() {
    if (!_shouldThunder) {
      _stopThunder();
      return;
    }
    _thunderController ??= AnimationController(
      duration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _scheduleThunder();
  }

  void _scheduleThunder() {
    _thunderTimer?.cancel();
    final seconds = 8 + _thunderRandom.nextInt(25);
    _thunderTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted || !_shouldThunder) return;
      await _thunderController?.forward(from: 0);
      if (mounted && _thunderRandom.nextBool()) {
        await Future<void>.delayed(const Duration(milliseconds: 70));
        if (mounted && _shouldThunder) {
          await _thunderController?.forward(from: 0);
        }
      }
      if (mounted) _scheduleThunder();
    });
  }

  void _stopThunder() {
    _thunderTimer?.cancel();
    _thunderTimer = null;
    _thunderController?.stop();
    _thunderController?.dispose();
    _thunderController = null;
  }

  void _handleSuppression() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _gustRandom = math.Random();
    _thunderRandom = math.Random();
    widget.interactionSuppressed?.addListener(_handleSuppression);
    _syncAnimation();
    _ensureGust();
    _ensureThunder();
  }

  @override
  void didUpdateWidget(AmbientCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interactionSuppressed != oldWidget.interactionSuppressed) {
      oldWidget.interactionSuppressed?.removeListener(_handleSuppression);
      widget.interactionSuppressed?.addListener(_handleSuppression);
    }
    final motionChanged =
        widget.reduceMotion != oldWidget.reduceMotion ||
        widget.intensity != oldWidget.intensity;
    if (motionChanged) _syncAnimation();
    // Re-evaluate gust scheduling when any of its inputs change so that a
    // new weather snapshot (gustFactor) or route intensity update takes effect.
    if (motionChanged ||
        widget.visualState != oldWidget.visualState ||
        widget.intensity != oldWidget.intensity) {
      _ensureGust();
    }
    if (motionChanged ||
        widget.visualState != oldWidget.visualState ||
        widget.reduceFlashing != oldWidget.reduceFlashing) {
      _ensureThunder();
    }
  }

  @override
  void dispose() {
    widget.interactionSuppressed?.removeListener(_handleSuppression);
    _stopAnimation();
    _stopGust();
    _stopThunder();
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
    final baseMotion = visualState?.motionIntensity ?? 0.16;

    // Page-level intensity scales every visual channel (design §9.2).
    final intensity = widget.intensity.clamp(0.0, 1.5);

    // Auto-decelerate while the user scrolls or the keyboard is open so the
    // background stops competing for attention (design §9.3).
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final suppressed =
        (widget.interactionSuppressed?.value ?? false) || keyboardOpen;
    final effectiveMotion = baseMotion * intensity * (suppressed ? 0.15 : 1.0);

    final cloudOpacity = ((visualState?.cloudOpacity ?? 0) * intensity).clamp(
      0.0,
      0.4,
    );
    final warmGlow = ((visualState?.warmGlow ?? 0) * 0.28 * intensity).clamp(
      0.0,
      0.4,
    );
    final gustFactor = visualState?.gustFactor ?? 0.0;

    Widget gradientLayer = _gradient(
      topColor,
      bottomColor,
      direction,
      motionOffset: 0,
    );

    if (_curvedAnimation != null) {
      final sources = <Listenable>[_curvedAnimation!];
      if (_gustController != null) sources.add(_gustController!);
      final merged = Listenable.merge(sources);
      gradientLayer = AnimatedBuilder(
        animation: merged,
        builder: (_, child) {
          final t = _curvedAnimation!.value;
          final gustPulse = _gustController?.value ?? 0;
          final baseOffset = (t - .5) * effectiveMotion;
          final gustOffset = suppressed
              ? 0.0
              : gustPulse * gustFactor * intensity * 0.3;
          final fallback = _gradient(
            topColor,
            bottomColor,
            direction,
            motionOffset: baseOffset + gustOffset,
          );
          return _withShader(fallback, visualState: visualState, time: t);
        },
      );
    } else {
      gradientLayer = _withShader(
        gradientLayer,
        visualState: visualState,
        time: 0,
      );
    }

    final precipIntensity =
        ((visualState?.precipitationIntensity ?? 0) * intensity).clamp(
          0.0,
          1.0,
        );

    return SizedBox.expand(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            gradientLayer,
            if (cloudOpacity > 0.001)
              ColoredBox(color: Colors.grey.withValues(alpha: cloudOpacity)),
            if (warmGlow > 0.001)
              ColoredBox(
                color: const Color(0xFFFF7043).withValues(alpha: warmGlow),
              ),
            if (widget.showWeatherTexture && precipIntensity > 0.01)
              CustomPaint(
                painter: _PrecipitationTexturePainter(
                  intensity: precipIntensity,
                  directionDegrees: visualState!.flowDirection,
                  isSnow:
                      visualState.precipitation == AmbientPrecipitation.snow,
                  phase: _curvedAnimation?.value ?? 0,
                ),
              ),
            if (widget.showWeatherTexture &&
                visualState?.thunderstorm == true &&
                !widget.reduceFlashing &&
                intensity > 0)
              _ThunderPulse(
                animation: _thunderController,
                intensity: intensity,
              ),
          ],
        ),
      ),
    );
  }

  Widget _withShader(
    Widget fallback, {
    required AmbientVisualState? visualState,
    required double time,
  }) {
    if (visualState == null || widget.renderer == AmbientRenderer.staticField) {
      return fallback;
    }
    return AmbientShaderSurface(
      visualState: visualState,
      time: widget.reduceMotion ? 0 : time * 20,
      lowQuality: widget.renderer == AmbientRenderer.reducedFragment,
      child: fallback,
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
    required this.phase,
  });

  final double intensity;
  final double directionDegrees;
  final bool isSnow;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .05 + intensity * .1)
      ..strokeWidth = isSnow ? 2 : 1;
    final radians = directionDegrees * math.pi / 180;
    final slant = math.sin(radians) * (8 + intensity * 22);
    final length = isSnow ? 3 + intensity * 6 : 12 + intensity * 34;
    final spacing = (42 - intensity * 24).clamp(16, 42);
    final fall = (phase * (isSnow ? 18 : 90)) % spacing;
    for (var x = -length; x < size.width + length; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing * 1.6) {
        final start = Offset(
          x + (isSnow ? math.sin(y + phase * 8) * 4 : 0),
          y + fall,
        );
        if (isSnow) {
          canvas.drawCircle(start, 1.2 + intensity * .9, paint);
        } else {
          canvas.drawLine(start, start + Offset(slant, length), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PrecipitationTexturePainter oldDelegate) =>
      oldDelegate.intensity != intensity ||
      oldDelegate.directionDegrees != directionDegrees ||
      oldDelegate.isSnow != isSnow ||
      oldDelegate.phase != phase;
}

class _ThunderPulse extends StatelessWidget {
  const _ThunderPulse({required this.animation, required this.intensity});

  final Animation<double>? animation;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    if (animation == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: animation!,
      builder: (_, _) {
        final pulse = Curves.easeOut.transform(animation!.value);
        return ColoredBox(
          color: Colors.white.withValues(
            alpha: (pulse * (1 - pulse) * .38 * intensity).clamp(0.0, 0.12),
          ),
        );
      },
    );
  }
}
