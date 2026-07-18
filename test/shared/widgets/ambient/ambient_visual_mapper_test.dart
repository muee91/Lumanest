import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

void main() {
  group('AmbientPalette', () {
    test('equality', () {
      const a = AmbientPalette(
        topColor: Color(0xFF000000),
        bottomColor: Color(0xFFFFFFFF),
      );
      const b = AmbientPalette(
        topColor: Color(0xFF000000),
        bottomColor: Color(0xFFFFFFFF),
      );
      const c = AmbientPalette(
        topColor: Color(0xFFFFFFFF),
        bottomColor: Color(0xFF000000),
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('AmbientVisualMapper', () {
    late AmbientVisualMapper mapper;

    setUp(() {
      mapper = const AmbientVisualMapper();
    });

    AmbientPalette resolve(WeatherType weather, DayPhase phase, Brightness b) =>
        mapper.resolve(weather, phase, b);

    test('clear weather daytime returns a clear sky palette', () {
      final palette = resolve(
        WeatherType.clear,
        DayPhase.day,
        Brightness.light,
      );

      expect(palette.topColor, isNot(palette.bottomColor));
      // Daylight starts with clear sky rather than the old beige wash.
      final top = palette.topColor;
      expect((top.b * 255).round(), greaterThan((top.r * 255).round()));
      expect((top.g * 255).round(), greaterThan((top.r * 255).round()));
    });

    test('clear weather dayPhase produces meaningfully different palettes', () {
      final dawn = resolve(WeatherType.clear, DayPhase.dawn, Brightness.light);
      final day = resolve(WeatherType.clear, DayPhase.day, Brightness.light);
      final sunset = resolve(
        WeatherType.clear,
        DayPhase.sunset,
        Brightness.light,
      );
      final blueHour = resolve(
        WeatherType.clear,
        DayPhase.blueHour,
        Brightness.light,
      );

      // Every dayPhase must produce a distinct palette.
      final palettes = {dawn, day, sunset, blueHour};
      expect(
        palettes.length,
        equals(4),
        reason:
            'Expected 4 distinct palettes for dawn/day/sunset/blueHour, '
            'but dayPhase is being ignored.',
      );

      // Dawn should lean warmer (more red) than day.
      expect(
        (dawn.topColor.r * 255).round(),
        greaterThan((day.topColor.r * 255).round()),
      );

      // Sunset should lean warmer (more red) than day.
      expect(
        (sunset.topColor.r * 255).round(),
        greaterThan((day.topColor.r * 255).round()),
      );

      // The blue-hour tint remains visually distinct from the day field.
      expect(blueHour.topColor, isNot(day.topColor));
    });

    test('clear weather nighttime returns dark palette', () {
      final palette = resolve(
        WeatherType.clear,
        DayPhase.night,
        Brightness.dark,
      );

      expect(palette.topColor, isNot(palette.bottomColor));
      // Dark colors: all channels low.
      expect((palette.topColor.r * 255).round(), lessThan(0x60));
      expect((palette.topColor.g * 255).round(), lessThan(0x60));
    });

    test('cloudy weather returns muted palette distinct from clear', () {
      final cloudy = resolve(
        WeatherType.cloudy,
        DayPhase.day,
        Brightness.light,
      );
      final clear = resolve(WeatherType.clear, DayPhase.day, Brightness.light);

      expect(cloudy, isNot(equals(clear)));
    });

    test('rain weather returns cool palette distinct from cloudy', () {
      final rain = resolve(WeatherType.rain, DayPhase.day, Brightness.light);
      final cloudy = resolve(
        WeatherType.cloudy,
        DayPhase.day,
        Brightness.light,
      );

      expect(rain, isNot(equals(cloudy)));
    });

    test(
      'thunder-like weather (rain at night dark) returns dramatic tones',
      () {
        final palette = resolve(
          WeatherType.rain,
          DayPhase.night,
          Brightness.dark,
        );

        // Dark, cool palette — blue channels prominent in dark mode rain.
        expect((palette.topColor.r * 255).round(), lessThan(0x40));
        expect((palette.topColor.g * 255).round(), lessThan(0x40));
      },
    );

    test('snow weather returns ice palette distinct from rain', () {
      final snow = resolve(WeatherType.snow, DayPhase.day, Brightness.light);
      final rain = resolve(WeatherType.rain, DayPhase.day, Brightness.light);

      expect(snow, isNot(equals(rain)));
    });

    test('dust weather returns dusty palette distinct from clear', () {
      final dust = resolve(WeatherType.dust, DayPhase.day, Brightness.light);
      final clear = resolve(WeatherType.clear, DayPhase.day, Brightness.light);

      expect(dust, isNot(equals(clear)));
    });

    test('all weather types return non-null palette for every day phase', () {
      for (final weather in WeatherType.values) {
        for (final phase in DayPhase.values) {
          for (final brightness in Brightness.values) {
            final palette = resolve(weather, phase, brightness);
            expect(palette, isNotNull);
            expect(palette.topColor, isNotNull);
            expect(palette.bottomColor, isNotNull);
          }
        }
      }
    });

    test('all physical display scenes produce distinct subtle accents', () {
      final palettes = <AmbientPalette>{};
      for (final scene in SceneType.values.where(
        (scene) => scene != SceneType.unknown,
      )) {
        palettes.add(
          mapper
              .resolveSnapshot(
                ContextSnapshot(
                  id: 'scene-${scene.name}',
                  observedAt: DateTime.utc(2026, 7, 16, 8),
                  expiresAt: DateTime.utc(2026, 7, 16, 8, 30),
                  primaryScene: scene,
                  dayPhase: DayPhase.day,
                  weather: WeatherType.clear,
                  activeRoute: false,
                ),
                Brightness.light,
              )
              .palette,
        );
      }

      expect(palettes, hasLength(5));
    });

    test('snapshot maps wind, rain and thunder into visual parameters', () {
      final state = mapper.resolveSnapshot(
        ContextSnapshot(
          id: 'storm',
          observedAt: DateTime.utc(2026, 7, 12),
          expiresAt: DateTime.utc(2026, 7, 12, 0, 15),
          primaryScene: SceneType.mountain,
          dayPhase: DayPhase.sunset,
          weather: WeatherType.rain,
          activeRoute: true,
          windDirectionDegrees: 285,
          windSpeedMetersPerSecond: 12,
          precipitationMillimeters: 6,
          safetyEventIds: const ['thunderstorm'],
        ),
        Brightness.dark,
      );

      expect(state.flowDirection, 285);
      expect(state.motionIntensity, greaterThan(.08));
      expect(state.precipitationIntensity, closeTo(.75, .001));
      expect(state.precipitation, AmbientPrecipitation.rain);
      expect(state.thunderstorm, isTrue);
    });

    test('snow maps to a visible snow texture even without a rain gauge', () {
      final state = mapper.resolveSnapshot(
        ContextSnapshot(
          id: 'snow',
          observedAt: DateTime.utc(2026, 7, 12),
          expiresAt: DateTime.utc(2026, 7, 12, 0, 15),
          primaryScene: SceneType.mountain,
          dayPhase: DayPhase.day,
          weather: WeatherType.snow,
          activeRoute: false,
        ),
        Brightness.light,
      );

      expect(state.precipitation, AmbientPrecipitation.snow);
      expect(state.precipitationIntensity, greaterThan(0));
    });

    test(
      'snapshot maps measured cloud cover and dawn warmth deterministically',
      () {
        final state = mapper.resolveSnapshot(
          ContextSnapshot(
            id: 'clear-dawn',
            observedAt: DateTime.utc(2026, 7, 12),
            expiresAt: DateTime.utc(2026, 7, 12, 0, 15),
            primaryScene: SceneType.mountain,
            dayPhase: DayPhase.dawn,
            weather: WeatherType.clear,
            activeRoute: false,
            cloudCoverPercent: 20,
          ),
          Brightness.light,
        );

        expect(state.cloudOpacity, closeTo(.08, .001));
        expect(state.warmGlow, greaterThan(0));
        expect(state.gustFactor, inInclusiveRange(0, 1));
      },
    );

    test('dense cloud suppresses warm glow and clamps visual channels', () {
      final state = mapper.resolveSnapshot(
        ContextSnapshot(
          id: 'cloudy-dawn',
          observedAt: DateTime.utc(2026, 7, 12),
          expiresAt: DateTime.utc(2026, 7, 12, 0, 15),
          primaryScene: SceneType.city,
          dayPhase: DayPhase.dawn,
          weather: WeatherType.cloudy,
          activeRoute: false,
          cloudCoverPercent: 140,
          windSpeedMetersPerSecond: 80,
        ),
        Brightness.light,
      );

      expect(state.cloudOpacity, .4);
      expect(state.warmGlow, 0);
      expect(state.gustFactor, 1);
      expect(state.motionIntensity, .4);
    });
  });
}
