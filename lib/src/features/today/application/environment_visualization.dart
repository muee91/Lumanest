import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';

enum EnvironmentMetricType {
  cloud,
  light,
  precipitation,
  wind,
  visibility,
  air,
  temperature,
}

class EnvironmentMetricCard {
  const EnvironmentMetricCard({
    required this.type,
    required this.label,
    required this.value,
    required this.summary,
    required this.priority,
    this.interactive = false,
  });

  final EnvironmentMetricType type;
  final String label;
  final String value;
  final String summary;
  final int priority;
  final bool interactive;
}

class CloudVisualization {
  const CloudVisualization({
    required this.totalCloudCoverPercent,
    required this.lowCloudCoverPercent,
    required this.middleCloudCoverPercent,
    required this.highCloudCoverPercent,
    required this.observedAt,
    required this.expiresAt,
    required this.isStale,
    required this.sourceLabel,
    required this.weatherAgreement,
    required this.scene,
    required this.dayPhase,
  });

  final double? totalCloudCoverPercent;
  final double? lowCloudCoverPercent;
  final double? middleCloudCoverPercent;
  final double? highCloudCoverPercent;
  final DateTime observedAt;
  final DateTime expiresAt;
  final bool isStale;
  final String sourceLabel;
  final String? weatherAgreement;
  final SceneType scene;
  final DayPhase dayPhase;

  bool get hasLayeredClouds =>
      lowCloudCoverPercent != null ||
      middleCloudCoverPercent != null ||
      highCloudCoverPercent != null;

  String get headline {
    final dominant = dominantLayer;
    final total = totalCloudCoverPercent;
    if (dominant != null) return '$dominant占主导';
    if (total == null) return '云层结构暂不完整';
    if (total >= 85) return '云层接近完全覆盖';
    if (total >= 60) return '云层偏多';
    if (total >= 30) return '云量适中';
    return '天空较开阔';
  }

  String get summary {
    final low = lowCloudCoverPercent;
    if (low != null && low >= 70) {
      return '低云较厚，低空太阳与远处山体可能受遮挡。';
    }
    final high = highCloudCoverPercent;
    if (high != null && high >= 45 && (low ?? 0) < 45) {
      return '高云较明显，日出日落前后可关注余晖变化。';
    }
    final total = totalCloudCoverPercent;
    if (total != null && total >= 80) {
      return '直射光条件受限，但柔光与低反差题材仍可利用。';
    }
    if (total != null && total <= 25) {
      return '云层较少，直射光明确，天空纹理可能偏弱。';
    }
    return '云层有一定层次，实际受光仍需结合太阳方向确认。';
  }

  String? get dominantLayer {
    final values = <MapEntry<String, double>>[];
    if (lowCloudCoverPercent case final value?) {
      values.add(MapEntry('低云', value));
    }
    if (middleCloudCoverPercent case final value?) {
      values.add(MapEntry('中云', value));
    }
    if (highCloudCoverPercent case final value?) {
      values.add(MapEntry('高云', value));
    }
    if (values.isEmpty) return null;
    final sorted = values..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.value >= 35 ? sorted.first.key : null;
  }

  String get compactLayerSummary {
    if (!hasLayeredClouds) {
      final total = totalCloudCoverPercent;
      return total == null ? '分层数据暂不可用' : '总云量 ${_percent(total)}';
    }
    return [
      if (lowCloudCoverPercent case final value?) '低 ${_percent(value)}',
      if (middleCloudCoverPercent case final value?) '中 ${_percent(value)}',
      if (highCloudCoverPercent case final value?) '高 ${_percent(value)}',
    ].join(' · ');
  }

  List<String> get photographyNotes {
    final notes = <String>[];
    final low = lowCloudCoverPercent;
    final middle = middleCloudCoverPercent;
    final high = highCloudCoverPercent;
    final total = totalCloudCoverPercent;

    if (dayPhase == DayPhase.dawn ||
        dayPhase == DayPhase.sunset ||
        dayPhase == DayPhase.blueHour) {
      if (low != null && low >= 65) {
        notes.add('低云可能遮挡接近地平线的太阳，建议优先观察太阳方向是否出现云隙。');
      } else if (high != null && high >= 35) {
        notes.add('高云具备承接余晖的条件，但颜色强度仍取决于低空是否通透。');
      }
      if (middle != null && middle >= 30 && middle <= 75) {
        notes.add('中云有机会形成局部明暗层次，适合保留一定天空比例。');
      }
    }

    if (scene == SceneType.lake) {
      notes.add(
        total != null && total >= 75
            ? '水岸更适合低反差、冷调和局部反光，不要只等待强烈晚霞。'
            : '水面可作为云层结构的第二画面，现场还需结合风速判断倒影完整度。',
      );
    } else if (scene == SceneType.mountain && low != null && low >= 55) {
      notes.add('低云可能形成云雾绕山，也可能完全遮峰；到场前应再次确认山体可见度。');
    } else if (scene == SceneType.city && total != null && total >= 70) {
      notes.add('建筑与人文题材会获得更均匀的柔光，可减少天空占比并利用地面反光。');
    }

    if (notes.isEmpty) {
      notes.add('当前云量只描述天空覆盖，不等同于已经出现可拍摄的光线。');
    }
    return List.unmodifiable(notes.take(3));
  }

  static String _percent(double value) => '${value.round()}%';
}

class EnvironmentVisualization {
  const EnvironmentVisualization({required this.cards, required this.cloud});

  final List<EnvironmentMetricCard> cards;
  final CloudVisualization? cloud;

  factory EnvironmentVisualization.fromSnapshot(
    ContextSnapshot snapshot, {
    SkyWindowForecast? skyWindow,
    required DateTime now,
  }) {
    final utcNow = now.toUtc();
    final usableSky = skyWindow != null && skyWindow.expiresAt.isAfter(utcNow)
        ? skyWindow
        : null;
    final atmosphere = usableSky?.current.atmosphere;
    final layeredCloudAvailable =
        atmosphere != null &&
        (atmosphere.lowCloudCoverPercent != null ||
            atmosphere.middleCloudCoverPercent != null ||
            atmosphere.highCloudCoverPercent != null);
    final totalCloud =
        atmosphere?.totalCloudCoverPercent ?? snapshot.cloudCoverPercent;
    final cloud = totalCloud == null && !layeredCloudAvailable
        ? null
        : CloudVisualization(
            totalCloudCoverPercent: totalCloud,
            lowCloudCoverPercent: atmosphere?.lowCloudCoverPercent,
            middleCloudCoverPercent: atmosphere?.middleCloudCoverPercent,
            highCloudCoverPercent: atmosphere?.highCloudCoverPercent,
            observedAt: usableSky?.current.observedAt ?? snapshot.observedAt,
            expiresAt: usableSky?.expiresAt ?? snapshot.expiresAt,
            isStale:
                snapshot.isStale ||
                snapshot.dataFreshness == ContextDataFreshness.stale,
            sourceLabel: usableSky == null
                ? 'Context 当前天气'
                : '公开天气分层云量 · 7Timer 仅作交叉核对',
            weatherAgreement: usableSky?.current.weatherAgreement,
            scene: snapshot.primaryScene,
            dayPhase: snapshot.dayPhase,
          );

    final cards = <EnvironmentMetricCard>[];
    void add(EnvironmentMetricCard? card) {
      if (card != null) cards.add(card);
    }

    add(
      cloud == null
          ? null
          : EnvironmentMetricCard(
              type: EnvironmentMetricType.cloud,
              label: '云层',
              value: cloud.totalCloudCoverPercent == null
                  ? '分层可用'
                  : '${cloud.totalCloudCoverPercent!.round()}%',
              summary: cloud.compactLayerSummary,
              priority: _priority(snapshot, EnvironmentMetricType.cloud),
              interactive: true,
            ),
    );

    final lightValue = _lightValue(snapshot, utcNow);
    if (lightValue != null) {
      add(
        EnvironmentMetricCard(
          type: EnvironmentMetricType.light,
          label: snapshot.solarElevationDegrees == null ? '光线时间' : '太阳高度',
          value: lightValue.$1,
          summary: lightValue.$2,
          priority: _priority(snapshot, EnvironmentMetricType.light),
        ),
      );
    }

    final weatherLabel = _weatherLabel(snapshot.weather);
    if (weatherLabel != null || snapshot.temperatureCelsius != null) {
      final temperature = snapshot.temperatureCelsius;
      add(
        EnvironmentMetricCard(
          type: EnvironmentMetricType.temperature,
          label: weatherLabel == null ? '温度' : '天气',
          value: weatherLabel == null
              ? '${temperature!.round()}°'
              : temperature == null
              ? weatherLabel
              : '$weatherLabel · ${temperature.round()}°',
          summary:
              snapshot.dataFreshness == ContextDataFreshness.fresh &&
                  !snapshot.isStale
              ? '当前环境观测'
              : '最近一次有效观测',
          priority: _priority(snapshot, EnvironmentMetricType.temperature),
        ),
      );
    }

    if (snapshot.precipitationMillimeters case final precipitation?) {
      add(
        EnvironmentMetricCard(
          type: EnvironmentMetricType.precipitation,
          label: '降水',
          value: '${precipitation.toStringAsFixed(1)} mm',
          summary: atmosphere?.precipitationProbabilityPercent == null
              ? _precipitationSummary(precipitation)
              : '未来时段概率 ${atmosphere!.precipitationProbabilityPercent!.round()}%',
          priority: _priority(snapshot, EnvironmentMetricType.precipitation),
        ),
      );
    }

    if (snapshot.windSpeedMetersPerSecond case final wind?) {
      final direction = _windDirection(snapshot.windDirectionDegrees);
      add(
        EnvironmentMetricCard(
          type: EnvironmentMetricType.wind,
          label: '风',
          value: direction == null
              ? '${wind.toStringAsFixed(1)} m/s'
              : '$direction · ${wind.toStringAsFixed(1)} m/s',
          summary: atmosphere?.windGustKmh == null
              ? _windSummary(wind)
              : '阵风约 ${(atmosphere!.windGustKmh! / 3.6).toStringAsFixed(1)} m/s',
          priority: _priority(snapshot, EnvironmentMetricType.wind),
        ),
      );
    }

    if (snapshot.visibilityKilometers case final visibility?) {
      add(
        EnvironmentMetricCard(
          type: EnvironmentMetricType.visibility,
          label: '能见度',
          value: _distance(visibility),
          summary: _visibilitySummary(visibility),
          priority: _priority(snapshot, EnvironmentMetricType.visibility),
        ),
      );
    }

    final air = snapshot.airQualityCategory?.trim();
    if (!snapshot.airQualityStale && air != null && air.isNotEmpty) {
      add(
        EnvironmentMetricCard(
          type: EnvironmentMetricType.air,
          label: '大气',
          value: air,
          summary: snapshot.primaryPollutant == null
              ? '空气质量观测'
              : '首要污染物 ${snapshot.primaryPollutant}',
          priority: _priority(snapshot, EnvironmentMetricType.air),
        ),
      );
    }

    cards.sort((a, b) => a.priority.compareTo(b.priority));
    return EnvironmentVisualization(
      cards: List.unmodifiable(cards.take(6)),
      cloud: cloud,
    );
  }

  static int _priority(ContextSnapshot snapshot, EnvironmentMetricType type) {
    if (snapshot.weather == WeatherType.rain ||
        snapshot.weather == WeatherType.snow) {
      const order = [
        EnvironmentMetricType.precipitation,
        EnvironmentMetricType.cloud,
        EnvironmentMetricType.wind,
        EnvironmentMetricType.visibility,
        EnvironmentMetricType.light,
        EnvironmentMetricType.temperature,
        EnvironmentMetricType.air,
      ];
      return order.indexOf(type);
    }
    if (snapshot.dayPhase == DayPhase.dawn ||
        snapshot.dayPhase == DayPhase.sunset ||
        snapshot.dayPhase == DayPhase.blueHour) {
      const order = [
        EnvironmentMetricType.cloud,
        EnvironmentMetricType.light,
        EnvironmentMetricType.visibility,
        EnvironmentMetricType.wind,
        EnvironmentMetricType.precipitation,
        EnvironmentMetricType.temperature,
        EnvironmentMetricType.air,
      ];
      return order.indexOf(type);
    }
    if (snapshot.dayPhase == DayPhase.night) {
      const order = [
        EnvironmentMetricType.cloud,
        EnvironmentMetricType.visibility,
        EnvironmentMetricType.air,
        EnvironmentMetricType.light,
        EnvironmentMetricType.wind,
        EnvironmentMetricType.precipitation,
        EnvironmentMetricType.temperature,
      ];
      return order.indexOf(type);
    }
    const order = [
      EnvironmentMetricType.cloud,
      EnvironmentMetricType.temperature,
      EnvironmentMetricType.light,
      EnvironmentMetricType.wind,
      EnvironmentMetricType.visibility,
      EnvironmentMetricType.precipitation,
      EnvironmentMetricType.air,
    ];
    return order.indexOf(type);
  }

  static (String, String)? _lightValue(ContextSnapshot snapshot, DateTime now) {
    final elevation = snapshot.solarElevationDegrees;
    final sunset = snapshot.sunset;
    final sunrise = snapshot.sunrise;
    if (elevation != null) {
      final event = sunset != null && sunset.isAfter(now)
          ? '日落 ${_time(sunset)}'
          : sunrise != null && sunrise.isAfter(now)
          ? '日出 ${_time(sunrise)}'
          : _phaseLabel(snapshot.dayPhase);
      final position = elevation >= 0 ? '地平线上方' : '地平线下方';
      return ('${elevation.toStringAsFixed(1)}°', '$position · $event');
    }
    if (sunset != null && sunset.isAfter(now)) {
      return (_time(sunset), '下一次日落');
    }
    if (sunrise != null && sunrise.isAfter(now)) {
      return (_time(sunrise), '下一次日出');
    }
    return null;
  }

  static String _phaseLabel(DayPhase phase) => switch (phase) {
    DayPhase.dawn => '晨光阶段',
    DayPhase.day => '日间光线',
    DayPhase.sunset => '落日阶段',
    DayPhase.blueHour => '蓝调阶段',
    DayPhase.night => '夜间环境',
  };

  static String? _weatherLabel(WeatherType value) => switch (value) {
    WeatherType.clear => '晴',
    WeatherType.cloudy => '多云',
    WeatherType.rain => '雨',
    WeatherType.snow => '雪',
    WeatherType.dust => '扬尘',
    WeatherType.unknown => null,
  };

  static String _precipitationSummary(double value) {
    if (value <= 0.05) return '当前无明显降水';
    if (value < 2.5) return '弱降水，留意器材防护';
    if (value < 8) return '降水明显，适合关注雨景与反光';
    return '降水较强，创作应服从安全与防护';
  }

  static String _windSummary(double value) {
    if (value < 1.5) return '风弱，水面与长曝光更稳定';
    if (value < 5.5) return '风力适中，留意水面纹理';
    if (value < 10.8) return '风力较强，三脚架需稳定';
    return '强风条件，优先确认安全与器材固定';
  }

  static String _visibilitySummary(double value) {
    if (value >= 30) return '远景通透条件较好';
    if (value >= 15) return '中远景层次基本可用';
    if (value >= 5) return '远景受限，适合近中景';
    return '能见度较低，优先近景与氛围题材';
  }

  static String _distance(double value) {
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$text km';
  }

  static String? _windDirection(double? degrees) {
    if (degrees == null) return null;
    const labels = ['北风', '东北风', '东风', '东南风', '南风', '西南风', '西风', '西北风'];
    return labels[((degrees + 22.5) ~/ 45) % labels.length];
  }

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';
}
