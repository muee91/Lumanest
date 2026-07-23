import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';

Map<String, Object?> assessment(String observedAt) => {
      'observedAt': observedAt,
      'conditionBand': 'favorable',
      'geometry': {
        'astronomicalNight': true,
        'sun': {
          'azimuthDegrees': 300.0,
          'altitudeDegrees': -24.0,
          'modelVersion': 'astronomy-engine-2.1.19',
        },
        'galacticCenter': {
          'azimuthDegrees': 142.0,
          'altitudeDegrees': 28.0,
          'modelVersion': 'iau-galactic-center-j2000.1',
        },
      },
      'terrain': {
        'status': 'ready',
        'horizonAltitudeDegrees': 8.0,
        'clearanceDegrees': 20.0,
        'obstructionDistanceKm': 6.0,
        'obstructionElevationMeters': 3200.0,
        'coverageRatio': 0.98,
      },
      'moon': {
        'azimuthDegrees': 270.0,
        'altitudeDegrees': -5.0,
        'illuminationFraction': 0.2,
        'phaseAngleDegrees': 126.0,
        'apparentMagnitude': -9.0,
        'angularSeparationFromGalacticCenterDegrees': 90.0,
        'terrainStatus': 'ready',
        'terrainHorizonAltitudeDegrees': 2.0,
        'terrainClearanceDegrees': -7.0,
        'terrainBlocked': true,
        'interferenceBand': 'low',
        'interferenceModelVersion': 'moon-directional-interference.1',
        'modelVersion': 'astronomy-engine-2.1.19',
      },
      'atmosphere': {
        'source': 'open-meteo-best-match',
        'totalCloudCoverPercent': 10.0,
        'lowCloudCoverPercent': 2.0,
        'middleCloudCoverPercent': 3.0,
        'highCloudCoverPercent': 5.0,
        'visibilityMeters': 30000.0,
        'precipitationProbabilityPercent': 0.0,
        'precipitationMm': 0.0,
        'relativeHumidityPercent': 50.0,
        'windSpeedKmh': 5.0,
        'windGustKmh': 10.0,
        'status': 'ready',
        'conditionBand': 'favorable',
        'limitations': <Object?>[],
      },
      'auxiliary': {
        'sevenTimer': null,
        'weatherAgreement': 'unavailable',
      },
      'lightPollution': {
        'status': 'ready',
        'direction': 'southeast',
        'azimuthDegrees': 142.0,
        'p90': 0.2,
        'relativeRadianceBand': 'dark',
        'coverageRatio': 0.95,
        'dominantDirection': 'east',
        'dominantAzimuthDegrees': 90.0,
        'dominantAngularSeparationDegrees': 52.0,
      },
      'limitations': <Object?>[],
    };

Map<String, Object?> fixture() => {
      'contractVersion': 1,
      'algorithmVersion': 'sky-window-forecast.1',
      'requestedCoordinate': {
        'latitude': 30.0,
        'longitude': 100.0,
        'system': 'wgs84',
      },
      'requestedStartAt': '2026-07-23T15:00:00.000Z',
      'endAt': '2026-07-23T21:00:00.000Z',
      'stepMinutes': 15,
      'generatedAt': '2026-07-23T15:00:00.000Z',
      'expiresAt': '2026-07-23T15:15:00.000Z',
      'current': assessment('2026-07-23T15:00:00.000Z'),
      'windows': [
        {
          'id': 'sky_window_1',
          'startAt': '2026-07-23T16:00:00.000Z',
          'endAt': '2026-07-23T18:00:00.000Z',
          'peakAt': '2026-07-23T17:00:00.000Z',
          'conditionBand': 'favorable',
          'sampleCount': 8,
          'favorableSamples': 8,
          'conditionalSamples': 0,
          'peakAssessment': assessment('2026-07-23T17:00:00.000Z'),
          'primaryReasons': <Object?>[],
        },
      ],
      'bestWindowId': 'sky_window_1',
      'confidence': {
        'band': 'medium',
        'criticalSourcesReady': true,
        'missingSources': <Object?>['seven_timer_auxiliary'],
        'conflicts': <Object?>[],
      },
      'calibration': {
        'status': 'unconfigured',
        'sampleCount': 0,
        'sqmMedian': null,
        'limitingMagnitudeMedian': null,
        'distanceKm': null,
        'source': null,
        'limitation': null,
      },
      'sources': <Object?>[],
    };

void main() {
  test('parses explainable sky-window forecast without probability', () {
    final value = SkyWindowForecast.fromJson(fixture());
    expect(value.bestWindow?.id, 'sky_window_1');
    expect(value.current.moon?.terrainBlocked, isTrue);
    expect(value.current.moon?.interferenceBand, MoonInterferenceBand.low);
    expect(value.current.terrain.clearanceDegrees, 20);
    expect(value.current.atmosphere.totalCloudCoverPercent, 10);
    expect(value.confidence.band, SkyWindowConfidenceBand.medium);
  });

  test('rejects unknown best-window references', () {
    final json = fixture()..['bestWindowId'] = 'missing';
    expect(() => SkyWindowForecast.fromJson(json), throwsFormatException);
  });
}
