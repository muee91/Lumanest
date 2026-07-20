import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String source;
  late AmbientPresetBundle bundle;

  setUpAll(() async {
    source = await rootBundle.loadString('assets/ambient/presets_v1.json');
    bundle = AmbientPresetBundle.fromJsonString(source);
  });

  test('bundled catalog parses ten unique reviewed-shape presets', () {
    expect(bundle.schemaVersion, 1);
    expect(bundle.presets, hasLength(10));
    expect(bundle.byId, hasLength(10));
    expect(
      bundle.presets.every((preset) => preset.reviewStatus == 'draft'),
      isTrue,
    );
  });

  test('selector follows weather and day phase deterministically', () {
    expect(
      bundle.select(weather: WeatherType.clear, dayPhase: DayPhase.sunset).id,
      'clear_sunset',
    );
    expect(
      bundle.select(weather: WeatherType.rain, dayPhase: DayPhase.day).id,
      'rain',
    );
    expect(
      bundle.select(weather: WeatherType.rain, dayPhase: DayPhase.night).id,
      'rain',
      reason: 'Weather semantics remain authoritative over day phase.',
    );
    expect(
      bundle
          .select(
            weather: WeatherType.clear,
            dayPhase: DayPhase.day,
            conserveEnergy: true,
          )
          .id,
      'energy_saver_static',
    );
  });

  test('quality override is applied and remains within validated bounds', () {
    final preset = bundle.require('rain');
    final reduced = preset.fieldFor(AmbientQualityTier.reduced);
    final staticField = preset.fieldFor(AmbientQualityTier.static);

    expect(reduced.timeSpeed, .08);
    expect(reduced.warpStrength, lessThan(preset.field.warpStrength));
    expect(staticField.timeSpeed, 0);
    expect(staticField.warpStrength, 0);
  });

  test('unsupported schema and unsafe sample values are rejected', () {
    expect(
      () => AmbientPresetBundle.fromJsonString(
        source.replaceFirst('"schemaVersion": 1', '"schemaVersion": 2'),
      ),
      throwsA(isA<AmbientPresetFormatException>()),
    );
    expect(
      () => AmbientPresetBundle.fromJsonString(
        source.replaceFirst('"timeSpeed": 0.16', '"timeSpeed": 2.9'),
      ),
      throwsA(isA<AmbientPresetFormatException>()),
    );
    expect(
      () => AmbientPresetBundle.fromJsonString(
        source.replaceFirst(
          '"colors": ["#CDE5EC", "#7EB4C2", "#F1E9DA"]',
          '"colors": ["#CDE5EC"]',
        ),
      ),
      throwsA(anyOf(isA<AmbientPresetFormatException>(), isA<ArgumentError>())),
    );
  });
}
