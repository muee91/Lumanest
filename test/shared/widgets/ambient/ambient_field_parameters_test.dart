import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';

void main() {
  test('field parameters use value equality and immutable colors', () {
    final first = _field();
    final second = _field();

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(() => first.colors.add(Colors.white), throwsUnsupportedError);
  });

  test('field parameters require exactly three colors', () {
    expect(
      () => _field(colors: const [Colors.black, Colors.white]),
      throwsArgumentError,
    );
  });

  test('validator rejects non-finite and out-of-range values', () {
    expect(
      () => AmbientPresetValidator.validateField(
        _field(timeSpeed: double.infinity),
        path: 'test',
      ),
      throwsA(isA<AmbientPresetFormatException>()),
    );
    expect(
      () => AmbientPresetValidator.validateField(
        _field(warpStrength: 3.8),
        path: 'test',
      ),
      throwsA(isA<AmbientPresetFormatException>()),
    );
  });
}

AmbientFieldParameters _field({
  List<Color> colors = const [Colors.blue, Colors.teal, Colors.orange],
  double timeSpeed = .2,
  double warpStrength = .8,
}) {
  return AmbientFieldParameters(
    colors: colors,
    timeSpeed: timeSpeed,
    colorBalance: 0,
    warpStrength: warpStrength,
    warpFrequency: 4,
    warpSpeed: .6,
    warpAmplitude: 60,
    blendAngleDegrees: 0,
    blendSoftness: .6,
    rotationAmountDegrees: 200,
    noiseScale: 1.8,
    grainAmount: .03,
    grainScale: 2,
    animateGrain: false,
    contrast: 1,
    gamma: 1,
    saturation: .9,
    center: Offset.zero,
    zoom: .95,
  );
}
