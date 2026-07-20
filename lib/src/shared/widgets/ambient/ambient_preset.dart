import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';

class AmbientPresetFormatException implements FormatException {
  const AmbientPresetFormatException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final Object? source;

  @override
  final int? offset;

  @override
  String toString() => 'AmbientPresetFormatException: $message';
}

@immutable
class AmbientFieldOverride {
  const AmbientFieldOverride({
    this.timeSpeed,
    this.colorBalance,
    this.warpStrength,
    this.warpFrequency,
    this.warpSpeed,
    this.warpAmplitude,
    this.blendAngleDegrees,
    this.blendSoftness,
    this.rotationAmountDegrees,
    this.noiseScale,
    this.grainAmount,
    this.grainScale,
    this.animateGrain,
    this.contrast,
    this.gamma,
    this.saturation,
    this.center,
    this.zoom,
  });

  final double? timeSpeed;
  final double? colorBalance;
  final double? warpStrength;
  final double? warpFrequency;
  final double? warpSpeed;
  final double? warpAmplitude;
  final double? blendAngleDegrees;
  final double? blendSoftness;
  final double? rotationAmountDegrees;
  final double? noiseScale;
  final double? grainAmount;
  final double? grainScale;
  final bool? animateGrain;
  final double? contrast;
  final double? gamma;
  final double? saturation;
  final Offset? center;
  final double? zoom;

  AmbientFieldParameters apply(AmbientFieldParameters base) {
    return base.copyWith(
      timeSpeed: timeSpeed,
      colorBalance: colorBalance,
      warpStrength: warpStrength,
      warpFrequency: warpFrequency,
      warpSpeed: warpSpeed,
      warpAmplitude: warpAmplitude,
      blendAngleDegrees: blendAngleDegrees,
      blendSoftness: blendSoftness,
      rotationAmountDegrees: rotationAmountDegrees,
      noiseScale: noiseScale,
      grainAmount: grainAmount,
      grainScale: grainScale,
      animateGrain: animateGrain,
      contrast: contrast,
      gamma: gamma,
      saturation: saturation,
      center: center,
      zoom: zoom,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AmbientFieldOverride &&
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
class AmbientPreset {
  AmbientPreset({
    required this.schemaVersion,
    required this.id,
    required this.label,
    required List<String> semanticTags,
    required this.field,
    Map<AmbientQualityTier, AmbientFieldOverride> qualityOverrides = const {},
    required this.transitionDuration,
    required this.minTextContrast,
    required this.reviewStatus,
  }) : semanticTags = List<String>.unmodifiable(semanticTags),
       qualityOverrides =
           Map<AmbientQualityTier, AmbientFieldOverride>.unmodifiable(
             qualityOverrides,
           );

  final int schemaVersion;
  final String id;
  final String label;
  final List<String> semanticTags;
  final AmbientFieldParameters field;
  final Map<AmbientQualityTier, AmbientFieldOverride> qualityOverrides;
  final Duration transitionDuration;
  final double minTextContrast;
  final String reviewStatus;

  AmbientFieldParameters fieldFor(AmbientQualityTier quality) {
    final resolved = qualityOverrides[quality]?.apply(field) ?? field;
    AmbientPresetValidator.validateField(resolved, path: '$id.$quality');
    return resolved;
  }

  @override
  bool operator ==(Object other) {
    return other is AmbientPreset &&
        other.schemaVersion == schemaVersion &&
        other.id == id &&
        other.label == label &&
        listEquals(other.semanticTags, semanticTags) &&
        other.field == field &&
        mapEquals(other.qualityOverrides, qualityOverrides) &&
        other.transitionDuration == transitionDuration &&
        other.minTextContrast == minTextContrast &&
        other.reviewStatus == reviewStatus;
  }

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    label,
    Object.hashAll(semanticTags),
    field,
    Object.hashAll(
      qualityOverrides.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    transitionDuration,
    minTextContrast,
    reviewStatus,
  );
}

@immutable
class AmbientPresetBundle {
  AmbientPresetBundle({
    required this.schemaVersion,
    required List<AmbientPreset> presets,
  }) : presets = List<AmbientPreset>.unmodifiable(presets),
       byId = Map<String, AmbientPreset>.unmodifiable({
         for (final preset in presets) preset.id: preset,
       }) {
    if (schemaVersion != 1) {
      throw AmbientPresetFormatException(
        'Unsupported preset bundle schemaVersion: $schemaVersion.',
      );
    }
    if (presets.isEmpty) {
      throw const AmbientPresetFormatException('Preset bundle is empty.');
    }
    if (byId.length != presets.length) {
      throw const AmbientPresetFormatException('Preset ids must be unique.');
    }
  }

  final int schemaVersion;
  final List<AmbientPreset> presets;
  final Map<String, AmbientPreset> byId;

  AmbientPreset require(String id) {
    final preset = byId[id];
    if (preset == null) {
      throw AmbientPresetFormatException('Unknown ambient preset: $id.');
    }
    return preset;
  }

  AmbientPreset select({
    required WeatherType weather,
    required DayPhase dayPhase,
    bool conserveEnergy = false,
  }) {
    if (conserveEnergy) return require('energy_saver_static');
    if (weather == WeatherType.rain) return require('rain');
    if (weather == WeatherType.snow) return require('snow');
    if (weather == WeatherType.dust) return require('dust');
    if (dayPhase == DayPhase.night) return require('night');
    if (dayPhase == DayPhase.blueHour) return require('blue_hour');
    if (weather == WeatherType.clear && dayPhase == DayPhase.dawn) {
      return require('clear_dawn');
    }
    if (weather == WeatherType.clear && dayPhase == DayPhase.sunset) {
      return require('clear_sunset');
    }
    return require(switch (weather) {
      WeatherType.clear => 'clear_day',
      WeatherType.cloudy => 'cloudy_day',
      WeatherType.rain => 'rain',
      WeatherType.snow => 'snow',
      WeatherType.dust => 'dust',
      WeatherType.unknown => 'cloudy_day',
    });
  }

  static Future<AmbientPresetBundle> load(
    AssetBundle assets, {
    String assetPath = 'assets/ambient/presets_v1.json',
  }) async {
    return fromJsonString(await assets.loadString(assetPath));
  }

  static AmbientPresetBundle fromJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw AmbientPresetFormatException(
        'Preset bundle is not valid JSON: ${error.message}',
        source,
        error.offset,
      );
    }
    final root = _map(decoded, r'$');
    final schemaVersion = _integer(root['schemaVersion'], r'$.schemaVersion');
    final rawPresets = _list(root['presets'], r'$.presets');
    final presets = <AmbientPreset>[];
    for (var index = 0; index < rawPresets.length; index += 1) {
      presets.add(
        _parsePreset(rawPresets[index], schemaVersion, r'$.presets[$index]'),
      );
    }
    return AmbientPresetBundle(schemaVersion: schemaVersion, presets: presets);
  }

  static AmbientPreset _parsePreset(
    Object? value,
    int schemaVersion,
    String path,
  ) {
    final map = _map(value, path);
    final id = _nonEmptyString(map['id'], '$path.id');
    final rawTags = _list(map['semanticTags'], '$path.semanticTags');
    final tags = [
      for (var index = 0; index < rawTags.length; index += 1)
        _nonEmptyString(rawTags[index], '$path.semanticTags[$index]'),
    ];
    final field = _parseField(_map(map['field'], '$path.field'), '$path.field');
    final qualityOverrides = <AmbientQualityTier, AmbientFieldOverride>{};
    final rawOverrides = map['qualityOverrides'];
    if (rawOverrides != null) {
      for (final entry in _map(
        rawOverrides,
        '$path.qualityOverrides',
      ).entries) {
        final tier = AmbientQualityTier.values
            .where((value) => value.name == entry.key)
            .firstOrNull;
        if (tier == null) {
          throw AmbientPresetFormatException(
            'Unknown quality tier at $path.qualityOverrides.${entry.key}.',
          );
        }
        qualityOverrides[tier] = _parseOverride(
          _map(entry.value, '$path.qualityOverrides.${entry.key}'),
          '$path.qualityOverrides.${entry.key}',
        );
      }
    }
    final preset = AmbientPreset(
      schemaVersion: schemaVersion,
      id: id,
      label: _nonEmptyString(map['label'], '$path.label'),
      semanticTags: tags,
      field: field,
      qualityOverrides: qualityOverrides,
      transitionDuration: Duration(
        milliseconds: _integer(
          map['transitionMilliseconds'],
          '$path.transitionMilliseconds',
        ),
      ),
      minTextContrast: _number(map['minTextContrast'], '$path.minTextContrast'),
      reviewStatus: _nonEmptyString(
        _map(map['review'], '$path.review')['status'],
        '$path.review.status',
      ),
    );
    AmbientPresetValidator.validate(preset);
    return preset;
  }

  static AmbientFieldParameters _parseField(
    Map<String, Object?> map,
    String path,
  ) {
    final rawColors = _list(map['colors'], '$path.colors');
    final colors = [
      for (var index = 0; index < rawColors.length; index += 1)
        _color(rawColors[index], '$path.colors[$index]'),
    ];
    return AmbientFieldParameters(
      colors: colors,
      timeSpeed: _number(map['timeSpeed'], '$path.timeSpeed'),
      colorBalance: _number(map['colorBalance'], '$path.colorBalance'),
      warpStrength: _number(map['warpStrength'], '$path.warpStrength'),
      warpFrequency: _number(map['warpFrequency'], '$path.warpFrequency'),
      warpSpeed: _number(map['warpSpeed'], '$path.warpSpeed'),
      warpAmplitude: _number(map['warpAmplitude'], '$path.warpAmplitude'),
      blendAngleDegrees: _number(
        map['blendAngleDegrees'],
        '$path.blendAngleDegrees',
      ),
      blendSoftness: _number(map['blendSoftness'], '$path.blendSoftness'),
      rotationAmountDegrees: _number(
        map['rotationAmountDegrees'],
        '$path.rotationAmountDegrees',
      ),
      noiseScale: _number(map['noiseScale'], '$path.noiseScale'),
      grainAmount: _number(map['grainAmount'], '$path.grainAmount'),
      grainScale: _number(map['grainScale'], '$path.grainScale'),
      animateGrain: _boolean(map['animateGrain'], '$path.animateGrain'),
      contrast: _number(map['contrast'], '$path.contrast'),
      gamma: _number(map['gamma'], '$path.gamma'),
      saturation: _number(map['saturation'], '$path.saturation'),
      center: Offset(
        _number(map['centerX'], '$path.centerX'),
        _number(map['centerY'], '$path.centerY'),
      ),
      zoom: _number(map['zoom'], '$path.zoom'),
    );
  }

  static AmbientFieldOverride _parseOverride(
    Map<String, Object?> map,
    String path,
  ) {
    double? optionalNumber(String key) =>
        map[key] == null ? null : _number(map[key], '$path.$key');
    return AmbientFieldOverride(
      timeSpeed: optionalNumber('timeSpeed'),
      colorBalance: optionalNumber('colorBalance'),
      warpStrength: optionalNumber('warpStrength'),
      warpFrequency: optionalNumber('warpFrequency'),
      warpSpeed: optionalNumber('warpSpeed'),
      warpAmplitude: optionalNumber('warpAmplitude'),
      blendAngleDegrees: optionalNumber('blendAngleDegrees'),
      blendSoftness: optionalNumber('blendSoftness'),
      rotationAmountDegrees: optionalNumber('rotationAmountDegrees'),
      noiseScale: optionalNumber('noiseScale'),
      grainAmount: optionalNumber('grainAmount'),
      grainScale: optionalNumber('grainScale'),
      animateGrain: map['animateGrain'] == null
          ? null
          : _boolean(map['animateGrain'], '$path.animateGrain'),
      contrast: optionalNumber('contrast'),
      gamma: optionalNumber('gamma'),
      saturation: optionalNumber('saturation'),
      center: map['centerX'] == null && map['centerY'] == null
          ? null
          : Offset(
              optionalNumber('centerX') ?? 0,
              optionalNumber('centerY') ?? 0,
            ),
      zoom: optionalNumber('zoom'),
    );
  }
}

abstract final class AmbientPresetValidator {
  static void validate(AmbientPreset preset) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(preset.id)) {
      throw AmbientPresetFormatException(
        'Preset id must use lowercase snake_case: ${preset.id}.',
      );
    }
    if (preset.semanticTags.isEmpty) {
      throw AmbientPresetFormatException(
        'Preset ${preset.id} requires at least one semanticTag.',
      );
    }
    if (preset.transitionDuration < Duration.zero ||
        preset.transitionDuration > const Duration(seconds: 5)) {
      throw AmbientPresetFormatException(
        'Preset ${preset.id} transition must be between 0 and 5000 ms.',
      );
    }
    if (!preset.minTextContrast.isFinite || preset.minTextContrast < 4.5) {
      throw AmbientPresetFormatException(
        'Preset ${preset.id} minTextContrast must be at least 4.5.',
      );
    }
    validateField(preset.field, path: preset.id);
    for (final quality in preset.qualityOverrides.keys) {
      preset.fieldFor(quality);
    }
  }

  static void validateField(
    AmbientFieldParameters field, {
    required String path,
  }) {
    _range(field.timeSpeed, 0, .8, '$path.timeSpeed');
    _range(field.colorBalance, -.3, .3, '$path.colorBalance');
    _range(field.warpStrength, 0, 1.8, '$path.warpStrength');
    _range(field.warpFrequency, 2.5, 7, '$path.warpFrequency');
    _range(field.warpSpeed, 0, 1.8, '$path.warpSpeed');
    _range(field.warpAmplitude, 24, 90, '$path.warpAmplitude');
    _range(field.blendAngleDegrees, -360, 360, '$path.blendAngleDegrees');
    _range(field.blendSoftness, .2, .92, '$path.blendSoftness');
    _range(field.rotationAmountDegrees, 0, 620, '$path.rotationAmountDegrees');
    _range(field.noiseScale, 1.2, 3.2, '$path.noiseScale');
    _range(field.grainAmount, 0, .075, '$path.grainAmount');
    _range(field.grainScale, 1, 4, '$path.grainScale');
    _range(field.contrast, .92, 1.18, '$path.contrast');
    _range(field.gamma, .9, 1.1, '$path.gamma');
    _range(field.saturation, .72, 1.16, '$path.saturation');
    _range(field.center.dx, -.25, .25, '$path.centerX');
    _range(field.center.dy, -.25, .25, '$path.centerY');
    _range(field.zoom, .82, 1.12, '$path.zoom');
  }

  static void _range(double value, double min, double max, String path) {
    if (!value.isFinite || value < min || value > max) {
      throw AmbientPresetFormatException(
        '$path must be finite and between $min and $max; got $value.',
      );
    }
  }
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw AmbientPresetFormatException('$path must be an object.');
  }
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) {
    throw AmbientPresetFormatException('$path must be an array.');
  }
  return value;
}

String _nonEmptyString(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw AmbientPresetFormatException('$path must be a non-empty string.');
  }
  return value;
}

double _number(Object? value, String path) {
  if (value is! num) {
    throw AmbientPresetFormatException('$path must be a number.');
  }
  final result = value.toDouble();
  if (!result.isFinite) {
    throw AmbientPresetFormatException('$path must be finite.');
  }
  return result;
}

int _integer(Object? value, String path) {
  if (value is! int) {
    throw AmbientPresetFormatException('$path must be an integer.');
  }
  return value;
}

bool _boolean(Object? value, String path) {
  if (value is! bool) {
    throw AmbientPresetFormatException('$path must be a boolean.');
  }
  return value;
}

Color _color(Object? value, String path) {
  final text = _nonEmptyString(value, path);
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(text);
  if (match == null) {
    throw AmbientPresetFormatException('$path must use #RRGGBB.');
  }
  return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
}
