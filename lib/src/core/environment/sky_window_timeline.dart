import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';

class SkyWindowTimelineSample {
  const SkyWindowTimelineSample({
    required this.validAt,
    required this.conditionBand,
    required this.sunAltitudeDegrees,
    required this.astronomicalNight,
    required this.totalCloudCoverPercent,
    required this.lowCloudCoverPercent,
    required this.middleCloudCoverPercent,
    required this.highCloudCoverPercent,
    required this.visibilityMeters,
    required this.precipitationProbabilityPercent,
    required this.precipitationMm,
    required this.relativeHumidityPercent,
    required this.windSpeedKmh,
    required this.windGustKmh,
    required this.weatherAgreement,
    required this.limitations,
  });

  final DateTime validAt;
  final SkyWindowConditionBand conditionBand;
  final double? sunAltitudeDegrees;
  final bool? astronomicalNight;
  final double? totalCloudCoverPercent;
  final double? lowCloudCoverPercent;
  final double? middleCloudCoverPercent;
  final double? highCloudCoverPercent;
  final double? visibilityMeters;
  final double? precipitationProbabilityPercent;
  final double? precipitationMm;
  final double? relativeHumidityPercent;
  final double? windSpeedKmh;
  final double? windGustKmh;
  final String weatherAgreement;
  final List<String> limitations;

  double? get visibilityKilometers =>
      visibilityMeters == null ? null : visibilityMeters! / 1000;
}

class SkyWindowTimelineForecast {
  const SkyWindowTimelineForecast({
    required this.forecast,
    required this.samples,
  });

  final SkyWindowForecast forecast;
  final List<SkyWindowTimelineSample> samples;

  factory SkyWindowTimelineForecast.fromJson(Map<String, Object?> json) {
    final forecast = SkyWindowForecast.fromJson(json);
    final rawSamples = _list(json['samples']);
    final maximumSamples =
        forecast.endAt.difference(forecast.requestedStartAt).inMinutes ~/
                forecast.stepMinutes +
            1;
    if (rawSamples.isEmpty ||
        rawSamples.length > 289 ||
        rawSamples.length != maximumSamples) {
      throw const FormatException('Invalid sky-window timeline size');
    }

    final samples = rawSamples
        .map((value) => _sample(_map(value)))
        .toList(growable: false);
    for (var index = 0; index < samples.length; index += 1) {
      final expected = forecast.requestedStartAt.add(
        Duration(minutes: forecast.stepMinutes * index),
      );
      if (samples[index].validAt.difference(expected).inMilliseconds.abs() > 1) {
        throw const FormatException('Invalid sky-window sample cadence');
      }
    }
    return SkyWindowTimelineForecast(
      forecast: forecast,
      samples: List.unmodifiable(samples),
    );
  }
}

SkyWindowTimelineSample _sample(Map<String, Object?> value) =>
    SkyWindowTimelineSample(
      validAt: _date(value['validAt']),
      conditionBand: SkyWindowConditionBand.values.byName(
        _requiredString(value['conditionBand'], 32),
      ),
      sunAltitudeDegrees: _nullableNumber(
        value['sunAltitudeDegrees'],
        -90,
        90,
      ),
      astronomicalNight: _nullableBoolean(value['astronomicalNight']),
      totalCloudCoverPercent: _nullableNumber(
        value['totalCloudCoverPercent'],
        0,
        100,
      ),
      lowCloudCoverPercent: _nullableNumber(
        value['lowCloudCoverPercent'],
        0,
        100,
      ),
      middleCloudCoverPercent: _nullableNumber(
        value['middleCloudCoverPercent'],
        0,
        100,
      ),
      highCloudCoverPercent: _nullableNumber(
        value['highCloudCoverPercent'],
        0,
        100,
      ),
      visibilityMeters: _nullableNumber(value['visibilityMeters'], 0, 100000),
      precipitationProbabilityPercent: _nullableNumber(
        value['precipitationProbabilityPercent'],
        0,
        100,
      ),
      precipitationMm: _nullableNumber(value['precipitationMm'], 0, 500),
      relativeHumidityPercent: _nullableNumber(
        value['relativeHumidityPercent'],
        0,
        100,
      ),
      windSpeedKmh: _nullableNumber(value['windSpeedKmh'], 0, 400),
      windGustKmh: _nullableNumber(value['windGustKmh'], 0, 500),
      weatherAgreement: _requiredString(value['weatherAgreement'], 32),
      limitations: _strings(value['limitations'], maximumItems: 32),
    );

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Expected list');
  return value;
}

List<String> _strings(Object? value, {required int maximumItems}) {
  final list = _list(value);
  if (list.length > maximumItems) throw const FormatException('Too many strings');
  return list
      .map((item) => _requiredString(item, 120))
      .toList(growable: false);
}

String _requiredString(Object? value, int maximum) {
  if (value is! String || value.isEmpty || value.length > maximum) {
    throw const FormatException('Expected bounded string');
  }
  return value;
}

double _number(Object? value, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum) {
    throw const FormatException('Expected bounded number');
  }
  return value.toDouble();
}

double? _nullableNumber(Object? value, double minimum, double maximum) =>
    value == null ? null : _number(value, minimum, maximum);

bool? _nullableBoolean(Object? value) {
  if (value == null) return null;
  if (value is! bool) throw const FormatException('Expected boolean');
  return value;
}

DateTime _date(Object? value) {
  final text = _requiredString(value, 40);
  final date = DateTime.tryParse(text)?.toUtc();
  if (date == null || !text.endsWith('Z')) {
    throw const FormatException('Expected UTC date');
  }
  return date;
}
