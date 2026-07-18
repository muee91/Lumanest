import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 液态玻璃（Liquid Glass）底部导航栏遮罩。
///
/// 使用 Fragment Shader 渲染一块半透玻璃质感的色板，覆盖在[child]上方，
/// 配合 [BackdropFilter.blur] 实现物理模糊。在不被支持的平台或测试环境中
/// 会退化为纯 Flutter 实现的玻璃效果。
class LiquidGlassNav extends StatefulWidget {
  const LiquidGlassNav({
    super.key,
    required this.child,
    this.borderRadius = 28.0,
    this.height = 70.0,
    this.padding = const EdgeInsets.fromLTRB(18, 0, 18, 12),
    this.margin = const EdgeInsets.fromLTRB(18, 0, 18, 12),
    this.tint,
    this.highlight,
    this.base,
    this.shadow,
    this.glassOpacity = 0.42,
    this.blur = 0.75,
    this.noiseAmount = 0.04,
    this.motionIntensity = 0.2,
    this.flowDirection = 45.0,
  });

  final Widget child;
  final double borderRadius;
  final double height;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? tint;
  final Color? highlight;
  final Color? base;
  final Color? shadow;
  final double glassOpacity;
  final double blur;
  final double noiseAmount;
  final double motionIntensity;
  final double flowDirection;

  @override
  State<LiquidGlassNav> createState() => _LiquidGlassNavState();
}

class _LiquidGlassNavState extends State<LiquidGlassNav>
    with SingleTickerProviderStateMixin {
  Future<FragmentProgram>? _program;
  FragmentShader? _shader;

  late final AnimationController _timeController;
  final _repaint = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _timeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _timeController.addListener(_onTick);
    _program = FragmentProgram.fromAsset('shaders/liquid_glass_nav.frag');
  }

  void _onTick() {
    _repaint.value = _timeController.value;
  }

  @override
  void dispose() {
    _timeController.removeListener(_onTick);
    _timeController.dispose();
    _repaint.dispose();
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  FragmentShader _shaderFor(FragmentProgram program) {
    if (_shader != null) return _shader!;
    final created = program.fragmentShader();
    _shader = created;
    return created;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final base = widget.base ?? (isDark ? const Color(0xFF242B2D) : const Color(0xFFF8F8F7));
    final tint = widget.tint ?? (isDark ? const Color(0xFF1A2A30) : const Color(0xFFEEF2F5));
    final highlight = widget.highlight ?? (isDark ? const Color(0xFF5A6D75) : const Color(0xFFFFFFFF));
    final shadow = widget.shadow ?? (isDark ? const Color(0xFF0C1012) : const Color(0xFFBBC2C6));

    final time = _timeController.value * 30;
    final flowRadians = widget.flowDirection * 3.141592653589793 / 180;

    return FutureBuilder<FragmentProgram>(
      future: _program,
      builder: (context, snapshot) {
        final program = snapshot.data;
        final useShader = program != null && !kIsWeb;

        return Container(
          key: const Key('v2-bottom-navigation'),
          height: widget.height + widget.padding.vertical,
          margin: widget.margin,
          padding: widget.padding,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: AnimatedBuilder(
                animation: _repaint,
                builder: (context, child) {
                  return CustomPaint(
                    painter: useShader
                        ? _LiquidGlassNavPainter(
                            shader: _shaderFor(program),
                            size: Size(
                              MediaQuery.sizeOf(context).width -
                                  widget.margin.horizontal,
                              widget.height,
                            ),
                            time: time,
                            flowRadians: flowRadians,
                            motion: widget.motionIntensity,
                            glassOpacity: widget.glassOpacity,
                            blur: widget.blur,
                            noiseAmount: widget.noiseAmount,
                            base: base,
                            tint: tint,
                            highlight: highlight,
                            shadow: shadow,
                          )
                        : _FallbackGlassPainter(
                            base: base,
                            tint: tint,
                            highlight: highlight,
                            shadow: shadow,
                          ),
                    child: child,
                  );
                },
                child: Container(
                  height: widget.height,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius - 2),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: .08),
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LiquidGlassNavPainter extends CustomPainter {
  _LiquidGlassNavPainter({
    required this.shader,
    required this.size,
    required this.time,
    required this.flowRadians,
    required this.motion,
    required this.glassOpacity,
    required this.blur,
    required this.noiseAmount,
    required this.base,
    required this.tint,
    required this.highlight,
    required this.shadow,
  }) : super(repaint: null);

  final FragmentShader shader;
  final Size size;
  final double time;
  final double flowRadians;
  final double motion;
  final double glassOpacity;
  final double blur;
  final double noiseAmount;
  final Color base;
  final Color tint;
  final Color highlight;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size paintSize) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, flowRadians)
      ..setFloat(4, motion)
      ..setFloat(5, glassOpacity)
      ..setFloat(6, blur)
      ..setFloat(7, noiseAmount);
    _setColor(shader, 8, base);
    _setColor(shader, 12, tint);
    _setColor(shader, 16, highlight);
    _setColor(shader, 20, shadow);

    canvas.drawRect(
      Offset.zero & paintSize,
      Paint()..shader = shader,
    );
  }

  static void _setColor(FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b)
      ..setFloat(index + 3, color.a);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassNavPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.size != size ||
      oldDelegate.flowRadians != flowRadians ||
      oldDelegate.glassOpacity != glassOpacity ||
      oldDelegate.blur != blur ||
      oldDelegate.noiseAmount != noiseAmount ||
      oldDelegate.base != base ||
      oldDelegate.tint != tint ||
      oldDelegate.highlight != highlight ||
      oldDelegate.shadow != shadow;
}

class _FallbackGlassPainter extends CustomPainter {
  _FallbackGlassPainter({
    required this.base,
    required this.tint,
    required this.highlight,
    required this.shadow,
  });

  final Color base;
  final Color tint;
  final Color highlight;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          base.withValues(alpha: 0.55),
          tint.withValues(alpha: 0.40),
          base.withValues(alpha: 0.50),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // 顶部高光
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          highlight.withValues(alpha: 0.22),
          highlight.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
      highlightPaint,
    );

    // 底部阴影
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          shadow.withValues(alpha: 0.12),
          shadow.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.6, size.width, size.height * 0.4),
      shadowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FallbackGlassPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.tint != tint ||
      oldDelegate.highlight != highlight ||
      oldDelegate.shadow != shadow;
}
