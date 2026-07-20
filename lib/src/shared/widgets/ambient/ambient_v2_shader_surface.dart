import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';

class AmbientV2ShaderSurface extends StatefulWidget {
  const AmbientV2ShaderSurface({
    super.key,
    required this.field,
    required this.time,
    required this.child,
    this.stormFactor = 0,
    this.rainStreaks = 0,
    this.flowRadians = 0,
    this.weatherKind = 0,
    this.dayPhaseKind = 1,
    this.cloudOpacity = 0,
    this.warmGlow = 0,
  });

  final AmbientFieldParameters field;
  final double time;
  final Widget child;
  final double stormFactor;
  final double rainStreaks;
  final double flowRadians;
  final double weatherKind;
  final double dayPhaseKind;
  final double cloudOpacity;
  final double warmGlow;

  @override
  State<AmbientV2ShaderSurface> createState() => _AmbientV2ShaderSurfaceState();
}

class _AmbientV2ShaderSurfaceState extends State<AmbientV2ShaderSurface> {
  late final Future<ui.FragmentProgram> _program = ui.FragmentProgram.fromAsset(
    'shaders/lumanest_ambient_v2.frag',
  );
  ui.FragmentShader? _shader;

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.FragmentProgram>(
    future: _program,
    builder: (context, snapshot) {
      final program = snapshot.data;
      if (program == null) return widget.child;
      _shader ??= program.fragmentShader();
      return CustomPaint(
        painter: _AmbientV2Painter(
          shader: _shader!,
          field: widget.field,
          time: widget.time,
          stormFactor: widget.stormFactor,
          rainStreaks: widget.rainStreaks,
          flowRadians: widget.flowRadians,
          weatherKind: widget.weatherKind,
          dayPhaseKind: widget.dayPhaseKind,
          cloudOpacity: widget.cloudOpacity,
          warmGlow: widget.warmGlow,
        ),
        child: const SizedBox.expand(),
      );
    },
  );
}

class _AmbientV2Painter extends CustomPainter {
  const _AmbientV2Painter({
    required this.shader,
    required this.field,
    required this.time,
    required this.stormFactor,
    required this.rainStreaks,
    required this.flowRadians,
    required this.weatherKind,
    required this.dayPhaseKind,
    required this.cloudOpacity,
    required this.warmGlow,
  });

  final ui.FragmentShader shader;
  final AmbientFieldParameters field;
  final double time;
  final double stormFactor;
  final double rainStreaks;
  final double flowRadians;
  final double weatherKind;
  final double dayPhaseKind;
  final double cloudOpacity;
  final double warmGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = field.colors;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, field.timeSpeed)
      ..setFloat(4, field.colorBalance)
      ..setFloat(5, field.warpStrength)
      ..setFloat(6, field.warpFrequency)
      ..setFloat(7, field.warpSpeed)
      ..setFloat(8, field.warpAmplitude)
      ..setFloat(9, field.blendAngleDegrees)
      ..setFloat(10, field.blendSoftness)
      ..setFloat(11, field.rotationAmountDegrees)
      ..setFloat(12, field.noiseScale)
      ..setFloat(13, field.grainAmount)
      ..setFloat(14, field.grainScale)
      ..setFloat(15, field.animateGrain ? 1 : 0)
      ..setFloat(16, field.contrast)
      ..setFloat(17, field.gamma)
      ..setFloat(18, field.saturation)
      ..setFloat(19, field.center.dx)
      ..setFloat(20, field.center.dy)
      ..setFloat(21, field.zoom);
    _setColor(shader, 22, colors[0]);
    _setColor(shader, 26, colors[1]);
    _setColor(shader, 30, colors[2]);
    shader
      ..setFloat(34, stormFactor.clamp(0.0, 1.0))
      ..setFloat(35, rainStreaks.clamp(0.0, 1.0))
      ..setFloat(36, flowRadians)
      ..setFloat(37, weatherKind)
      ..setFloat(38, dayPhaseKind);
    shader
      ..setFloat(39, cloudOpacity.clamp(0.0, 0.4))
      ..setFloat(40, warmGlow.clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  void _setColor(ui.FragmentShader shader, int index, Color color) {
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b)
      ..setFloat(index + 3, color.a);
  }

  @override
  bool shouldRepaint(covariant _AmbientV2Painter oldDelegate) =>
      oldDelegate.field != field ||
      oldDelegate.time != time ||
      oldDelegate.stormFactor != stormFactor ||
      oldDelegate.rainStreaks != rainStreaks ||
      oldDelegate.flowRadians != flowRadians ||
      oldDelegate.weatherKind != weatherKind ||
      oldDelegate.dayPhaseKind != dayPhaseKind ||
      oldDelegate.cloudOpacity != cloudOpacity ||
      oldDelegate.warmGlow != warmGlow;
}
