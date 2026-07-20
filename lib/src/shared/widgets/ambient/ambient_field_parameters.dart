import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

enum AmbientQualityTier { full, balanced, reduced, static }

@immutable
class AmbientFieldParameters {
  AmbientFieldParameters({
    required List<Color> colors,
    required this.timeSpeed,
    required this.colorBalance,
    required this.warpStrength,
    required this.warpFrequency,
    required this.warpSpeed,
    required this.warpAmplitude,
    required this.blendAngleDegrees,
    required this.blendSoftness,
    required this.rotationAmountDegrees,
    required this.noiseScale,
    required this.grainAmount,
    required this.grainScale,
    required this.animateGrain,
    required this.contrast,
    required this.gamma,
    required this.saturation,
    required this.center,
    required this.zoom,
  }) : colors = List<Color>.unmodifiable(colors) {
    if (colors.length != 3) {
      throw ArgumentError.value(
        colors.length,
        'colors.length',
        'Ambient fields require exactly three colors.',
      );
    }
  }

  final List<Color> colors;
  final double timeSpeed;
  final double colorBalance;
  final double warpStrength;
  final double warpFrequency;
  final double warpSpeed;
  final double warpAmplitude;
  final double blendAngleDegrees;
  final double blendSoftness;
  final double rotationAmountDegrees;
  final double noiseScale;
  final double grainAmount;
  final double grainScale;
  final bool animateGrain;
  final double contrast;
  final double gamma;
  final double saturation;
  final Offset center;
  final double zoom;

  AmbientFieldParameters copyWith({
    List<Color>? colors,
    double? timeSpeed,
    double? colorBalance,
    double? warpStrength,
    double? warpFrequency,
    double? warpSpeed,
    double? warpAmplitude,
    double? blendAngleDegrees,
    double? blendSoftness,
    double? rotationAmountDegrees,
    double? noiseScale,
    double? grainAmount,
    double? grainScale,
    bool? animateGrain,
    double? contrast,
    double? gamma,
    double? saturation,
    Offset? center,
    double? zoom,
  }) {
    return AmbientFieldParameters(
      colors: colors ?? this.colors,
      timeSpeed: timeSpeed ?? this.timeSpeed,
      colorBalance: colorBalance ?? this.colorBalance,
      warpStrength: warpStrength ?? this.warpStrength,
      warpFrequency: warpFrequency ?? this.warpFrequency,
      warpSpeed: warpSpeed ?? this.warpSpeed,
      warpAmplitude: warpAmplitude ?? this.warpAmplitude,
      blendAngleDegrees: blendAngleDegrees ?? this.blendAngleDegrees,
      blendSoftness: blendSoftness ?? this.blendSoftness,
      rotationAmountDegrees:
          rotationAmountDegrees ?? this.rotationAmountDegrees,
      noiseScale: noiseScale ?? this.noiseScale,
      grainAmount: grainAmount ?? this.grainAmount,
      grainScale: grainScale ?? this.grainScale,
      animateGrain: animateGrain ?? this.animateGrain,
      contrast: contrast ?? this.contrast,
      gamma: gamma ?? this.gamma,
      saturation: saturation ?? this.saturation,
      center: center ?? this.center,
      zoom: zoom ?? this.zoom,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AmbientFieldParameters &&
        listEquals(other.colors, colors) &&
        other.timeSpeed == timeSpeed &&
        other.colorBalance == colorBalance &&
        other.warpStrength == warpStrength &&
        other.warpFrequency == warpFrequency &&
        other.warpSpeed == warpSpeed &&
        other.warpAmplitude == warpAmplitude &&
        other.blendAngleDegrees == blendAngleDegrees &&
        other.blendSoftness == blendSoftness &&
        other.rotationAmountDegrees == rotationAmountDegrees &&
        other.noiseScale == noiseScale &&
        other.grainAmount == grainAmount &&
        other.grainScale == grainScale &&
        other.animateGrain == animateGrain &&
        other.contrast == contrast &&
        other.gamma == gamma &&
        other.saturation == saturation &&
        other.center == center &&
        other.zoom == zoom;
  }

  @override
  int get hashCode => Object.hashAll([
    ...colors,
    timeSpeed,
    colorBalance,
    warpStrength,
    warpFrequency,
    warpSpeed,
    warpAmplitude,
    blendAngleDegrees,
    blendSoftness,
    rotationAmountDegrees,
    noiseScale,
    grainAmount,
    grainScale,
    animateGrain,
    contrast,
    gamma,
    saturation,
    center,
    zoom,
  ]);
}

@immutable
class AmbientVisualComposition {
  const AmbientVisualComposition({
    required this.semanticState,
    required this.field,
    required this.quality,
    required this.transitionDuration,
  });

  final AmbientVisualState semanticState;
  final AmbientFieldParameters field;
  final AmbientQualityTier quality;
  final Duration transitionDuration;

  @override
  bool operator ==(Object other) {
    return other is AmbientVisualComposition &&
        other.semanticState == semanticState &&
        other.field == field &&
        other.quality == quality &&
        other.transitionDuration == transitionDuration;
  }

  @override
  int get hashCode =>
      Object.hash(semanticState, field, quality, transitionDuration);
}
