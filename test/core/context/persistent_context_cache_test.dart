import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/persistent_context_cache.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'round-trips a complete context snapshot across cache instances',
    () async {
      final preferences = SharedPreferencesAsync();
      const key = 'context-cache-roundtrip';
      final first = PersistentContextCache(preferences, storageKey: key);
      final now = DateTime.utc(2026, 7, 13, 10);
      final snapshot = ContextSnapshot(
        id: 'live-context',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.lake,
        dayPhase: DayPhase.sunset,
        weather: WeatherType.cloudy,
        activeRoute: false,
        opportunityIds: const ['reflection'],
        safetyEventIds: const ['strong-wind'],
        wildlifeEventIds: const ['regional-wildlife'],
        events: [
          ContextEvent(
            id: 'reflection',
            channel: ContextEventChannel.opportunity,
            source: ContextEventSource.rule,
            observedAt: now,
            expiresAt: now.add(const Duration(minutes: 15)),
            confidence: .82,
          ),
        ],
        wildlifeActivity: RegionalWildlifeActivity(
          radiusKilometers: 20,
          occurrenceSampleSize: 3,
          taxa: const [
            WildlifeTaxon(
              scientificName: 'Lutra lutra',
              commonName: '水獭',
              group: WildlifeGroup.mammal,
              records: 3,
            ),
          ],
        ),
        location: const GeoPoint(latitude: 30.25, longitude: 120.15),
        temperatureCelsius: 22,
        windSpeedMetersPerSecond: 5,
        windDirectionDegrees: 180,
        visibilityKilometers: 12,
        precipitationMillimeters: 0,
        cloudCoverPercent: 70,
        solarElevationDegrees: 4,
        solarAzimuthDegrees: 270,
        sunrise: now.subtract(const Duration(hours: 10)),
        sunset: now.add(const Duration(minutes: 20)),
      );

      await first.write(snapshot);
      final restored = await PersistentContextCache(
        preferences,
        storageKey: key,
      ).readLatest();

      expect(restored?.id, snapshot.id);
      expect(restored?.primaryScene, SceneType.lake);
      expect(restored?.events.single.confidence, .82);
      expect(restored?.wildlifeActivity?.taxa.single.commonName, '水獭');
      expect(restored?.location?.coordinateSystem, CoordinateSystem.wgs84);
      expect(restored?.sunset, snapshot.sunset);
    },
  );

  test('rejects malformed and unsupported cache values safely', () async {
    final preferences = SharedPreferencesAsync();
    const key = 'context-cache-malformed';
    await preferences.setString(key, '{broken');
    expect(
      await PersistentContextCache(preferences, storageKey: key).readLatest(),
      isNull,
    );

    await preferences.setString(key, '{"version":999}');
    expect(
      await PersistentContextCache(preferences, storageKey: key).readLatest(),
      isNull,
    );
  });

  test('clear removes the persisted environment snapshot', () async {
    final preferences = SharedPreferencesAsync();
    const key = 'context-cache-clear';
    final cache = PersistentContextCache(preferences, storageKey: key);
    final now = DateTime.utc(2026, 7, 13, 10);
    await cache.write(
      ContextSnapshot(
        id: 'private-context',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
      ),
    );

    await cache.clear();

    expect(await cache.readLatest(), isNull);
  });
}
