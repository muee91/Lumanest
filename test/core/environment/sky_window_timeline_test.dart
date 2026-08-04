import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/environment/sky_window_timeline.dart';

void main() {
  test('parses a complete bounded 15-minute timeline', () {
    final value = SkyWindowTimelineForecast.fromJson(_fixture());
    expect(value.samples, hasLength(25));
    expect(value.samples.first.validAt, value.forecast.requestedStartAt);
    expect(value.samples.last.validAt, value.forecast.endAt);
    expect(value.samples[4].totalCloudCoverPercent, 24);
    expect(value.samples[4].visibilityKilometers, 24);
    expect(value.samples[4].weatherAgreement, 'aligned');
  });

  test('rejects missing, oversized, or irregular samples', () {
    final missing = _fixture()..remove('samples');
    expect(
      () => SkyWindowTimelineForecast.fromJson(missing),
      throwsFormatException,
    );

    final irregular = _fixture();
    final samples = irregular['samples']! as List<Object?>;
    samples[3] = {
      ...(samples[3]! as Map<String, Object?>),
      'validAt': '2026-08-04T10:46:00.000Z',
    };
    expect(
      () => SkyWindowTimelineForecast.fromJson(irregular),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _fixture() {
  final start = DateTime.utc(2026, 8, 4, 10);
  final end = start.add(const Duration(hours: 6));
  return {
    'contractVersion': 1,
    'algorithmVersion': 'sky-window-forecast.1',
    'requestedCoordinate': {
      'latitude': 30.27,
      'longitude': 120.15,
      'system': 'wgs84',
    },
    'requestedStartAt': start.toIso8601String(),
    'endAt': end.toIso8601String(),
    'stepMinutes': 15,
    'generatedAt': start.toIso8601String(),
    'expiresAt': start.add(const Duration(minutes: 15)).toIso8601String(),
    'current': _assessment(start),
    'samples': [
      for (var index = 0; index <= 24; index += 1)
        _sample(start.add(Duration(minutes: 15 * index)), index),
    ],
    'windows': <Object?>[],
    'bestWindowId': null,
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
}

Map<String, Object?> _sample(DateTime validAt, int index) => {
      'validAt': validAt.toIso8601String(),
      'conditionBand': index.isEven ? 'conditional' : 'favorable',
      'sunAltitudeDegrees': 4.0 - index,
      'astronomicalNight': index > 12,
      'totalCloudCoverPercent': 20.0 + index,
      'lowCloudCoverPercent': 8.0 + index / 2,
      'middleCloudCoverPercent': 12.0 + index / 2,
      'highCloudCoverPercent': 18.0 + index / 3,
      'visibilityMeters': 20000.0 + index * 1000,
      'precipitationProbabilityPercent': index.toDouble(),
      'precipitationMm': 0.0,
      'relativeHumidityPercent': 60.0,
      'windSpeedKmh': 12.0,
      'windGustKmh': 18.0,
      'weatherAgreement': 'aligned',
      'limitations': <Object?>[],
    };

Map<String, Object?> _assessment(DateTime observedAt) => {
      'observedAt': observedAt.toIso8601String(),
      'conditionBand': 'conditional',
      'geometry': {
        'astronomicalNight': false,
        'sun': {
          'azimuthDegrees': 270.0,
          'altitudeDegrees': 4.0,
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
        'horizonAltitudeDegrees': 2.0,
        'clearanceDegrees': 26.0,
        'obstructionDistanceKm': 6.0,
        'coverageRatio': 0.98,
      },
      'moon': null,
      'atmosphere': {
        'source': 'open-meteo-best-match',
        'totalCloudCoverPercent': 20.0,
        'lowCloudCoverPercent': 8.0,
        'middleCloudCoverPercent': 12.0,
        'highCloudCoverPercent': 18.0,
        'visibilityMeters': 20000.0,
        'precipitationProbabilityPercent': 0.0,
        'precipitationMm': 0.0,
        'relativeHumidityPercent': 60.0,
        'windSpeedKmh': 12.0,
        'windGustKmh': 18.0,
        'status': 'ready',
        'conditionBand': 'conditional',
        'limitations': <Object?>[],
      },
      'auxiliary': {
        'sevenTimer': null,
        'weatherAgreement': 'unavailable',
      },
      'lightPollution': {
        'status': 'ready',
        'direction': 'west',
        'p90': 0.2,
        'relativeRadianceBand': 'dark',
        'coverageRatio': 0.95,
        'dominantDirection': 'east',
        'dominantAngularSeparationDegrees': 90.0,
      },
      'limitations': <Object?>[],
    };
