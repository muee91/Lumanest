import 'dart:ui';

import 'package:flutter/material.dart';

import 'ambient_visual_mapper.dart';

/// GPU color field used only when the rendering policy permits it.
///
/// Loading is intentionally fallible: unsupported devices and widget tests
/// retain the caller's deterministic gradient fallback rather than exposing a
/// black surface or delaying first paint.
class AmbientShaderSurface extends StatefulWidget {
  const AmbientShaderSurface({
    super.key,
    required this.visualState,
    required this.time,
    required this.child,
    this.lowQuality = false,
    this.onShaderCreated,
    this.onShaderDisposed,
  });

  final AmbientVisualState visualState;
  final double time;
  final Widget child;
  final bool lowQuality;
  final VoidCallback? onShaderCreated;
  final VoidCallback? onShaderDisposed;

  @override
  State<AmbientShaderSurface> createState() => _AmbientShaderSurfaceState();
}

class _AmbientShaderSurfaceState extends State<AmbientShaderSurface> {
  Future<FragmentProgram>? _program;
  FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _program = FragmentProgram.fromAsset('shaders/lumanest_ambient.frag');
  }

  @override
  void dispose() {
    if (_shader != null) {
      _shader!.dispose();
      widget.onShaderDisposed?.call();
    }
    _shader = null;
    super.dispose();
  }

  FragmentShader _shaderFor(FragmentProgram program) {
    final existing = _shader;
    if (existing != null) return existing;
    final created = program.fragmentShader();
    _shader = created;
    widget.onShaderCreated?.call();
    return created;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FragmentProgram>(
    future: _program,
    builder: (context, snapshot) {
      final program = snapshot.data;
      if (program == null) return widget.child;
      return CustomPaint(
        painter: _AmbientShaderPainter(
          shader: _shaderFor(program),
          visualState: widget.visualState,
          time: widget.time,
          lowQuality: widget.lowQuality,
        ),
        child: const SizedBox.expand(),
      );
    },
  );
}

class _AmbientShaderPainter extends CustomPainter {
  const _AmbientShaderPainter({
    required this.shader,
    required this.visualState,
    required this.time,
    required this.lowQuality,
  });

  final FragmentShader shader;
  final AmbientVisualState visualState;
  final double time;
  final bool lowQuality;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = visualState.palette;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, visualState.flowRadians)
      ..setFloat(
        4,
        lowQuality
            ? visualState.motionIntensity * .38
            : visualState.motionIntensity,
      )
      ..setFloat(5, visualState.cloudOpacity)
      ..setFloat(6, visualState.warmGlow)
      ..setFloat(7, visualState.stormFactor)
      ..setFloat(8, _rainStreaksFor(visualState));
    _setColor(shader, 9, palette.topColor);
    _setColor(shader, 13, palette.bottomColor);
    _setColor(shader, 17, visualState.accentColor);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  double _rainStreaksFor(AmbientVisualState state) {
    if (state.precipitation != AmbientPrecipitation.rain) return 0.0;
    return state.precipitationIntensity;
  }

  void _setColor(FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b)
      ..setFloat(index + 3, color.a);
  }

  @override
  bool shouldRepaint(covariant _AmbientShaderPainter oldDelegate) =>
      oldDelegate.visualState != visualState ||
      oldDelegate.time != time ||
      oldDelegate.lowQuality != lowQuality;
}
