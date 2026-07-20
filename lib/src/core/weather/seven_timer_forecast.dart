enum SevenTimerProduct { astro, meteo, two }

enum SevenTimerSourceStatus { fresh, aging, stale }

class SevenTimerRangeValue {
  const SevenTimerRangeValue({
    required this.level,
    required this.min,
    required this.max,
    required this.unit,
  });

  final int level;
  final double? min;
  final double? max;
  final String unit;
}

class SevenTimerWind {
  const SevenTimerWind({required this.direction, required this.speed});

  final String? direction;
  final SevenTimerRangeValue? speed;
}

sealed class SevenTimerPoint {
  const SevenTimerPoint({required this.validAt});

  final DateTime validAt;
}

class SevenTimerAstroPoint extends SevenTimerPoint {
  const SevenTimerAstroPoint({
    required super.validAt,
    required this.cloudCover,
    required this.seeing,
    required this.transparency,
    required this.humidity,
    required this.wind,
    required this.temperatureCelsius,
    required this.liftedIndex,
    required this.precipitationType,
  });

  final SevenTimerRangeValue? cloudCover;
  final SevenTimerRangeValue? seeing;
  final SevenTimerRangeValue? transparency;
  final SevenTimerRangeValue? humidity;
  final SevenTimerWind? wind;
  final double? temperatureCelsius;
  final double? liftedIndex;
  final String? precipitationType;
}

class SevenTimerHumidityProfilePoint {
  const SevenTimerHumidityProfilePoint({
    required this.layer,
    required this.humidity,
  });

  final String layer;
  final SevenTimerRangeValue humidity;
}

class SevenTimerWindProfilePoint {
  const SevenTimerWindProfilePoint({
    required this.layer,
    required this.directionDegrees,
    required this.speed,
  });

  final String layer;
  final double? directionDegrees;
  final SevenTimerRangeValue? speed;
}

class SevenTimerPrecipitation {
  const SevenTimerPrecipitation({required this.type, required this.amount});

  final String? type;
  final SevenTimerRangeValue? amount;
}

class SevenTimerMeteoPoint extends SevenTimerPoint {
  const SevenTimerMeteoPoint({
    required super.validAt,
    required this.totalCloudCover,
    required this.lowCloudCover,
    required this.middleCloudCover,
    required this.highCloudCover,
    required this.humidityProfile,
    required this.windProfile,
    required this.pressureMslHpa,
    required this.precipitation,
    required this.snowDepth,
  });

  final SevenTimerRangeValue? totalCloudCover;
  final SevenTimerRangeValue? lowCloudCover;
  final SevenTimerRangeValue? middleCloudCover;
  final SevenTimerRangeValue? highCloudCover;
  final List<SevenTimerHumidityProfilePoint> humidityProfile;
  final List<SevenTimerWindProfilePoint> windProfile;
  final double? pressureMslHpa;
  final SevenTimerPrecipitation? precipitation;
  final SevenTimerRangeValue? snowDepth;
}

class SevenTimerTwoPoint extends SevenTimerPoint {
  const SevenTimerTwoPoint({
    required super.validAt,
    required this.cloudCover,
    required this.temperatureMinCelsius,
    required this.temperatureMaxCelsius,
    required this.humidity,
    required this.wind,
    required this.liftedIndex,
    required this.weatherCode,
  });

  final SevenTimerRangeValue? cloudCover;
  final double? temperatureMinCelsius;
  final double? temperatureMaxCelsius;
  final SevenTimerRangeValue? humidity;
  final SevenTimerWind? wind;
  final double? liftedIndex;
  final String? weatherCode;
}

class SevenTimerForecast {
  SevenTimerForecast({
    required this.product,
    required this.sourceInitAt,
    required this.fetchedAt,
    required this.sourceStatus,
    required this.cacheStatus,
    required this.isStaleCache,
    required List<SevenTimerPoint> points,
  }) : points = List.unmodifiable(points);

  final SevenTimerProduct product;
  final DateTime sourceInitAt;
  final DateTime fetchedAt;
  final SevenTimerSourceStatus sourceStatus;
  final String cacheStatus;
  final bool isStaleCache;
  final List<SevenTimerPoint> points;
}
