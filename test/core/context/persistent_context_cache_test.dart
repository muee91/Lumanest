import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_cache.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/persistent_context_cache.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
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
            geoScope: ContextGeoScope.point,
            safetyLevel: ContextSafetyLevel.info,
            allowedAction: ContextAction.openExplore,
          ),
          ContextEvent(
            id: 'astronomy-123456789abc',
            channel: ContextEventChannel.opportunity,
            source: ContextEventSource.astronomyCatalog,
            observedAt: now,
            expiresAt: now.add(const Duration(hours: 2)),
            confidence: 1,
            geoScope: ContextGeoScope.regional,
            safetyLevel: ContextSafetyLevel.info,
            allowedAction: ContextAction.openAuthority,
            title: '英仙座流星雨极大期',
            sourceUri: Uri.parse('https://science.nasa.gov/meteor-showers/'),
          ),
        ],
        wildlifeActivity: RegionalWildlifeActivity(
          contractVersion: 2,
          radiusKilometers: 20,
          occurrenceSampleSize: 3,
          scannedOccurrenceSampleSize: 5,
          eligibleOccurrenceSampleSize: 3,
          datasetReferencesTruncated: false,
          qualityPolicy: WildlifeQualityPolicy(
            acceptedLicenses: const ['CC-BY-4.0'],
            acceptedBasisOfRecord: const ['HUMAN_OBSERVATION'],
            maximumCoordinateUncertaintyMeters: 10000,
            maximumDatasetReferences: 8,
            excludesSevereGeospatialIssues: true,
          ),
          historicalRecordConcentration: WildlifeHistoricalRecordConcentration(
            recordsWithMonth: 3,
            recordsWithTime: 2,
            months: const [WildlifeMonthConcentration(month: 5, records: 3)],
            timePeriods: const [
              WildlifePeriodConcentration(
                period: WildlifeObservationPeriod.dawn,
                records: 2,
              ),
            ],
          ),
          datasets: [
            WildlifeDatasetReference(
              datasetKey: '11111111-1111-4111-8111-111111111111',
              title: 'Regional observations',
              publisher: 'Open Nature Lab',
              licenses: const ['CC-BY-4.0'],
              records: 3,
              citation: 'Open Nature Lab (2026). Regional observations.',
              url: Uri.parse(
                'https://www.gbif.org/dataset/11111111-1111-4111-8111-111111111111',
              ),
            ),
          ],
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
        airQualityIndex: 86,
        airQualityCategory: '良',
        primaryPollutant: 'PM2.5',
        airQualityObservedAt: now.subtract(const Duration(minutes: 5)),
        airQualityStale: false,
        solarElevationDegrees: 4,
        solarAzimuthDegrees: 270,
        sunrise: now.subtract(const Duration(hours: 10)),
        sunset: now.add(const Duration(minutes: 20)),
        remoteGeneratedAt: now,
        dataFreshness: ContextDataFreshness.fresh,
        moonPhase: MoonPhase.waxingCrescent,
        moonIllumination: .2,
        routeMode: ContextRouteMode.none,
        routeStage: ContextRouteStage.none,
        allowedActions: const [
          ContextAction.openExplore,
          ContextAction.openAuthority,
        ],
      );

      await first.write(snapshot);
      final restored = await PersistentContextCache(
        preferences,
        storageKey: key,
      ).readLatest();

      expect(restored?.id, snapshot.id);
      expect(restored?.primaryScene, SceneType.lake);
      expect(restored?.events.first.confidence, .82);
      expect(restored?.wildlifeActivity?.taxa.single.commonName, '水獭');
      expect(restored?.wildlifeActivity?.contractVersion, 2);
      expect(restored?.wildlifeActivity?.scannedOccurrenceSampleSize, 5);
      expect(restored?.wildlifeActivity?.eligibleOccurrenceSampleSize, 3);
      expect(
        restored?.wildlifeActivity?.historicalRecordConcentration?.summary,
        '5月 · 晨间',
      );
      expect(
        restored?.wildlifeActivity?.datasets.single.publisher,
        'Open Nature Lab',
      );
      expect(restored?.location?.coordinateSystem, CoordinateSystem.wgs84);
      expect(restored?.sunset, snapshot.sunset);
      expect(restored?.moonPhase, MoonPhase.waxingCrescent);
      expect(restored?.airQualityIndex, 86);
      expect(restored?.airQualityCategory, '良');
      expect(restored?.primaryPollutant, 'PM2.5');
      expect(restored?.airQualityStale, isFalse);
      expect(restored?.events.first.allowedAction, ContextAction.openExplore);
      expect(restored?.events.last.title, '英仙座流星雨极大期');
      expect(restored?.events.last.allowedAction, ContextAction.openAuthority);
      expect(restored?.events.last.sourceUri?.scheme, 'https');
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

  group('server manifest', () {
    test(
      'round-trips a manifest with all fields across cache instances',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'manifest-roundtrip';
        final cache = PersistentContextCache(preferences, storageKey: key);
        final now = DateTime.utc(2026, 7, 13, 10);
        final snapshot = ContextSnapshot(
          id: 'manifest-test',
          observedAt: now,
          expiresAt: now.add(const Duration(minutes: 15)),
          primaryScene: SceneType.city,
          dayPhase: DayPhase.day,
          weather: WeatherType.clear,
          activeRoute: false,
          serverManifest: ServerManifest(
            layout: ServerManifestLayout.opportunity,
            primaryEventId: 'primary-1',
            secondaryEventIds: const ['secondary-1', 'secondary-2'],
            safetyEventIds: const ['safety-1', 'safety-2'],
          ),
        );

        await cache.write(snapshot);
        final restored = await PersistentContextCache(
          preferences,
          storageKey: key,
        ).readLatest();

        expect(restored?.serverManifest, isNotNull);
        expect(
          restored?.serverManifest?.layout,
          ServerManifestLayout.opportunity,
        );
        expect(restored?.serverManifest?.primaryEventId, 'primary-1');
        expect(restored?.serverManifest?.secondaryEventIds, [
          'secondary-1',
          'secondary-2',
        ]);
        expect(restored?.serverManifest?.safetyEventIds, [
          'safety-1',
          'safety-2',
        ]);
      },
    );

    test('round-trips a manifest with only layout (null ids)', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-minimal';
      final cache = PersistentContextCache(preferences, storageKey: key);
      final now = DateTime.utc(2026, 7, 13, 10);
      final snapshot = ContextSnapshot(
        id: 'manifest-minimal',
        observedAt: now,
        expiresAt: now.add(const Duration(minutes: 15)),
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        serverManifest: ServerManifest(layout: ServerManifestLayout.quiet),
      );

      await cache.write(snapshot);
      final restored = await PersistentContextCache(
        preferences,
        storageKey: key,
      ).readLatest();

      expect(restored?.serverManifest?.layout, ServerManifestLayout.quiet);
      expect(restored?.serverManifest?.primaryEventId, isNull);
      expect(restored?.serverManifest?.secondaryEventIds, isEmpty);
      expect(restored?.serverManifest?.safetyEventIds, isEmpty);
    });

    test(
      'reads null serverManifest from old-format snapshot (no key)',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'manifest-absent-key';
        // Hand-craft a JSON cache entry without the serverManifest key.
        final encoded = jsonEncode({
          'version': 2,
          'snapshot': {
            'id': 'no-manifest',
            'observedAt': '2026-07-13T10:00:00.000Z',
            'expiresAt': '2026-07-13T10:15:00.000Z',
            'primaryScene': 'city',
            'dayPhase': 'day',
            'weather': 'clear',
            'activeRoute': false,
            'dataFreshness': 'fresh',
            'routeMode': 'none',
            'routeStage': 'none',
            'events': [],
            'isStale': false,
          },
        });
        await preferences.setString(key, encoded);

        final restored = await PersistentContextCache(
          preferences,
          storageKey: key,
        ).readLatest();

        expect(restored?.id, 'no-manifest');
        expect(restored?.serverManifest, isNull);
      },
    );

    test('returns null when manifest has unknown layout', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-bad-layout';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'bad-layout',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'bogus_layout',
            'primaryEventId': null,
            'secondaryEventIds': [],
            'safetyEventIds': [],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test('returns null when secondaryEventIds exceeds 2', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-too-many-secondary';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'too-many-secondary',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'quiet',
            'primaryEventId': null,
            'secondaryEventIds': ['a', 'b', 'c'],
            'safetyEventIds': [],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test('returns null when secondaryEventIds contain duplicates', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-dup-secondary';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'dup-secondary',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'quiet',
            'primaryEventId': null,
            'secondaryEventIds': ['dup', 'dup'],
            'safetyEventIds': [],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test('returns null when safetyEventIds contain duplicates', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-dup-safety';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'dup-safety',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'quiet',
            'primaryEventId': null,
            'secondaryEventIds': [],
            'safetyEventIds': ['dup', 'dup'],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test('returns null when secondaryEventIds contain empty string', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-empty-secondary';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'empty-secondary',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'quiet',
            'primaryEventId': null,
            'secondaryEventIds': [''],
            'safetyEventIds': [],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test('returns null when safetyEventIds contain empty string', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-empty-safety';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'empty-safety',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'quiet',
            'primaryEventId': null,
            'secondaryEventIds': [],
            'safetyEventIds': [''],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test('returns null when primaryEventId is empty string', () async {
      final preferences = SharedPreferencesAsync();
      const key = 'manifest-empty-primary';
      final encoded = jsonEncode({
        'version': 2,
        'snapshot': {
          'id': 'empty-primary',
          'observedAt': '2026-07-13T10:00:00.000Z',
          'expiresAt': '2026-07-13T10:15:00.000Z',
          'primaryScene': 'city',
          'dayPhase': 'day',
          'weather': 'clear',
          'activeRoute': false,
          'dataFreshness': 'fresh',
          'routeMode': 'none',
          'routeStage': 'none',
          'events': [],
          'isStale': false,
          'serverManifest': {
            'layout': 'quiet',
            'primaryEventId': '',
            'secondaryEventIds': [],
            'safetyEventIds': [],
          },
        },
      });
      await preferences.setString(key, encoded);

      expect(
        await PersistentContextCache(preferences, storageKey: key).readLatest(),
        isNull,
      );
    });

    test(
      'returns null when primaryEventId appears in secondaryEventIds',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'manifest-primary-in-secondary';
        final encoded = jsonEncode({
          'version': 2,
          'snapshot': {
            'id': 'primary-in-secondary',
            'observedAt': '2026-07-13T10:00:00.000Z',
            'expiresAt': '2026-07-13T10:15:00.000Z',
            'primaryScene': 'city',
            'dayPhase': 'day',
            'weather': 'clear',
            'activeRoute': false,
            'dataFreshness': 'fresh',
            'routeMode': 'none',
            'routeStage': 'none',
            'events': [],
            'isStale': false,
            'serverManifest': {
              'layout': 'quiet',
              'primaryEventId': 'shared-id',
              'secondaryEventIds': ['shared-id'],
              'safetyEventIds': [],
            },
          },
        });
        await preferences.setString(key, encoded);

        expect(
          await PersistentContextCache(
            preferences,
            storageKey: key,
          ).readLatest(),
          isNull,
        );
      },
    );
  });

  group('stale-write guard', () {
    ContextSnapshot snapshot({
      required String id,
      required DateTime generatedAt,
      required DateTime expiresAt,
    }) {
      return ContextSnapshot(
        id: id,
        observedAt: generatedAt,
        expiresAt: expiresAt,
        primaryScene: SceneType.city,
        dayPhase: DayPhase.day,
        weather: WeatherType.clear,
        activeRoute: false,
        remoteGeneratedAt: generatedAt,
      );
    }

    test(
      'InMemory: older late-arriving write does not overwrite newer state',
      () async {
        final cache = InMemoryContextCache();
        final older = snapshot(
          id: 'older',
          generatedAt: DateTime.utc(2026, 7, 13, 10),
          expiresAt: DateTime.utc(2026, 7, 13, 10, 15),
        );
        final newer = snapshot(
          id: 'newer',
          generatedAt: DateTime.utc(2026, 7, 13, 11),
          expiresAt: DateTime.utc(2026, 7, 13, 11, 15),
        );

        await cache.write(older);
        await cache.write(newer);
        // Older request completes later.
        await cache.write(older);

        final latest = await cache.readLatest();
        expect(latest?.id, 'newer');
      },
    );

    test(
      'Persistent: older late-arriving write does not overwrite newer state',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'stale-write-guard-late';
        final cache = PersistentContextCache(preferences, storageKey: key);
        final older = snapshot(
          id: 'older',
          generatedAt: DateTime.utc(2026, 7, 13, 10),
          expiresAt: DateTime.utc(2026, 7, 13, 10, 15),
        );
        final newer = snapshot(
          id: 'newer',
          generatedAt: DateTime.utc(2026, 7, 13, 11),
          expiresAt: DateTime.utc(2026, 7, 13, 11, 15),
        );

        await cache.write(older);
        await cache.write(newer);
        await cache.write(older);

        final latest = await cache.readLatest();
        expect(latest?.id, 'newer');
      },
    );

    test(
      'Persistent: concurrent writes do not reverse-overwrite the cache',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'stale-write-guard-concurrent';
        final cache = PersistentContextCache(preferences, storageKey: key);

        final older = snapshot(
          id: 'older',
          generatedAt: DateTime.utc(2026, 7, 13, 10),
          expiresAt: DateTime.utc(2026, 7, 13, 10, 15),
        );
        final newer = snapshot(
          id: 'newer',
          generatedAt: DateTime.utc(2026, 7, 13, 11),
          expiresAt: DateTime.utc(2026, 7, 13, 11, 15),
        );

        // Fire both writes without awaiting. The internal chain serializes
        // them; regardless of completion order the newer snapshot must win.
        final results = await Future.wait([
          cache.write(newer),
          cache.write(older),
        ]);

        expect(results, [null, null]);
        final latest = await cache.readLatest();
        expect(latest?.id, 'newer');
      },
    );

    test(
      'Persistent: equal remoteGeneratedAt allows the second write through',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'stale-write-guard-equal';
        final cache = PersistentContextCache(preferences, storageKey: key);
        final generatedAt = DateTime.utc(2026, 7, 13, 10);
        final first = snapshot(
          id: 'first',
          generatedAt: generatedAt,
          expiresAt: DateTime.utc(2026, 7, 13, 10, 15),
        );
        final second = snapshot(
          id: 'second',
          generatedAt: generatedAt,
          expiresAt: DateTime.utc(2026, 7, 13, 10, 20),
        );

        await cache.write(first);
        await cache.write(second);

        final latest = await cache.readLatest();
        expect(latest?.id, 'second');
      },
    );

    test(
      'Persistent: falls back to expiresAt when remoteGeneratedAt is null',
      () async {
        final preferences = SharedPreferencesAsync();
        const key = 'stale-write-guard-expires';
        final cache = PersistentContextCache(preferences, storageKey: key);
        final older = ContextSnapshot(
          id: 'older',
          observedAt: DateTime.utc(2026, 7, 13, 9),
          expiresAt: DateTime.utc(2026, 7, 13, 10, 15),
          primaryScene: SceneType.city,
          dayPhase: DayPhase.day,
          weather: WeatherType.clear,
          activeRoute: false,
        );
        final newer = ContextSnapshot(
          id: 'newer',
          observedAt: DateTime.utc(2026, 7, 13, 10),
          expiresAt: DateTime.utc(2026, 7, 13, 11, 15),
          primaryScene: SceneType.city,
          dayPhase: DayPhase.day,
          weather: WeatherType.clear,
          activeRoute: false,
        );

        await cache.write(newer);
        await cache.write(older);

        final latest = await cache.readLatest();
        expect(latest?.id, 'newer');
      },
    );

    test(
      'Persistent: a failed write does not poison subsequent writes',
      () async {
        final preferences = _FailingThenOkPreferences(
          const _FailingPreferences(),
        );
        const key = 'stale-write-guard-failure';
        final cache = PersistentContextCache(preferences, storageKey: key);
        final first = snapshot(
          id: 'first',
          generatedAt: DateTime.utc(2026, 7, 13, 10),
          expiresAt: DateTime.utc(2026, 7, 13, 10, 15),
        );
        final second = snapshot(
          id: 'second',
          generatedAt: DateTime.utc(2026, 7, 13, 11),
          expiresAt: DateTime.utc(2026, 7, 13, 11, 15),
        );

        // First write fails (underlying storage error) but must not poison
        // the chain — the second write should still succeed.
        await expectLater(cache.write(first), throwsA(isA<Object>()));
        await cache.write(second);

        final latest = await cache.readLatest();
        expect(latest?.id, 'second');
      },
    );
  });
}

/// [SharedPreferencesAsync] stub whose first [setString] call throws and the
/// second succeeds against an in-memory map. Used to verify a single write
/// failure does not poison the serialized write chain.
class _FailingThenOkPreferences implements SharedPreferencesAsync {
  _FailingThenOkPreferences(this._failer);

  final _FailingPreferences _failer;
  final Map<String, Object> _store = {};
  final _FailingPreferencesState _state = _FailingPreferencesState();

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<String?> getString(String key) async {
    if (_store case {'value': final value}) return value as String;
    return null;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _state.setStringCalls += 1;
    if (_state.setStringCalls == 1) {
      return _failer.setString(key, value);
    }
    _store['value'] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _store.remove('value');
    return true;
  }

  @override
  Future<void> clear({Set<String>? allowList}) async {
    _store.clear();
  }

  @override
  noSuchMethod(Invocation invocation) => _failer.noSuchMethod(invocation);
}

class _FailingPreferencesState {
  int setStringCalls = 0;
}

class _FailingPreferences implements SharedPreferencesAsync {
  const _FailingPreferences();

  @override
  Future<bool> setString(String key, String value) => throw StateError('boom');

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<bool> containsKey(String key) async => false;

  @override
  Future<bool> remove(String key) async => true;

  @override
  Future<void> clear({Set<String>? allowList}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}
