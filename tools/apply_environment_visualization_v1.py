from pathlib import Path

ROOT = Path('.')


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


# ---------------------------------------------------------------------------
# Dependency and assets
# ---------------------------------------------------------------------------
pubspec_path = ROOT / 'pubspec.yaml'
pubspec = pubspec_path.read_text(encoding='utf-8')
if '  flutter_svg:' not in pubspec:
    pubspec = pubspec.replace(
        '  cupertino_icons: ^1.0.8\n',
        '  cupertino_icons: ^1.0.8\n  flutter_svg: ^2.3.0\n',
        1,
    )
if '    - assets/icons/environment/\n' not in pubspec:
    pubspec = pubspec.replace(
        '    - assets/ambient/\n',
        '    - assets/ambient/\n    - assets/icons/environment/\n',
        1,
    )
pubspec_path.write_text(pubspec, encoding='utf-8')

svg_assets = {
    'cloud_layers.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 9.7a4.3 4.3 0 0 1 8.2-1.6 3.6 3.6 0 1 1 1.1 6.9H6.4a2.7 2.7 0 1 1 .1-5.3Z"/><path d="M5 18h14M8 21h8"/></svg>''',
    'light.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 17h16M6.5 17a5.5 5.5 0 0 1 11 0"/><path d="M12 3v4M4.9 7.2l2.8 2M19.1 7.2l-2.8 2M3 12h4M17 12h4"/></svg>''',
    'wind.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8h10.5a2.5 2.5 0 1 0-2.1-3.9M3 12h16a2 2 0 1 1-1.7 3M3 16h8.5a2.5 2.5 0 1 1-2.1 3.9"/></svg>''',
    'visibility.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M2.8 12s3.5-5.2 9.2-5.2 9.2 5.2 9.2 5.2-3.5 5.2-9.2 5.2S2.8 12 2.8 12Z"/><circle cx="12" cy="12" r="2.7"/></svg>''',
    'precipitation.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6.7 13.5a4.2 4.2 0 0 1 7.9-2 3.3 3.3 0 1 1 1 6.3H6.7a2.2 2.2 0 1 1 0-4.3Z"/><path d="m8 20-.7 1.2M12 20l-.7 1.2M16 20l-.7 1.2"/></svg>''',
    'air.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 18c4.7-.4 8.3-3.4 9.4-8.2 1.8 2.4 2.5 5.7.4 8.3-2.1 2.7-6.3 2.8-9.8-.1Z"/><path d="M8 16c2.4-1.1 4.2-2.8 5.6-5.2M4 7h7M3 11h5"/></svg>''',
    'temperature.svg': '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M10 5a2 2 0 0 1 4 0v8.2a4 4 0 1 1-4 0V5Z"/><path d="M12 8v7"/></svg>''',
}
for filename, content in svg_assets.items():
    write(f'assets/icons/environment/{filename}', content)

# ---------------------------------------------------------------------------
# Visualization domain model
# ---------------------------------------------------------------------------
write('lib/src/features/today/application/environment_visualization.dart', r'''import 'package:luma_nest/src/core/context/context_snapshot.dart';
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
    final values = <String, double>{
      if (lowCloudCoverPercent case final value?) '低云': value,
      if (middleCloudCoverPercent case final value?) '中云': value,
      if (highCloudCoverPercent case final value?) '高云': value,
    };
    if (values.isEmpty) return null;
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
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
      notes.add(total != null && total >= 75
          ? '水岸更适合低反差、冷调和局部反光，不要只等待强烈晚霞。'
          : '水面可作为云层结构的第二画面，现场还需结合风速判断倒影完整度。');
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
    final layeredCloudAvailable = atmosphere != null &&
        (atmosphere.lowCloudCoverPercent != null ||
            atmosphere.middleCloudCoverPercent != null ||
            atmosphere.highCloudCoverPercent != null);
    final totalCloud = atmosphere?.totalCloudCoverPercent ??
        snapshot.cloudCoverPercent;
    final cloud = totalCloud == null && !layeredCloudAvailable
        ? null
        : CloudVisualization(
            totalCloudCoverPercent: totalCloud,
            lowCloudCoverPercent: atmosphere?.lowCloudCoverPercent,
            middleCloudCoverPercent: atmosphere?.middleCloudCoverPercent,
            highCloudCoverPercent: atmosphere?.highCloudCoverPercent,
            observedAt: usableSky?.current.observedAt ?? snapshot.observedAt,
            expiresAt: usableSky?.expiresAt ?? snapshot.expiresAt,
            isStale: snapshot.isStale ||
                snapshot.dataFreshness == ContextDataFreshness.stale,
            sourceLabel: usableSky == null
                ? 'Context 当前天气'
                : 'Open-Meteo 分层云量 · 7Timer 辅助校验',
            weatherAgreement: usableSky?.current.weatherAgreement,
            scene: snapshot.primaryScene,
            dayPhase: snapshot.dayPhase,
          );

    final cards = <EnvironmentMetricCard>[];
    void add(EnvironmentMetricCard? card) {
      if (card != null) cards.add(card);
    }

    add(cloud == null
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
          ));

    final lightValue = _lightValue(snapshot, utcNow);
    if (lightValue != null) {
      add(EnvironmentMetricCard(
        type: EnvironmentMetricType.light,
        label: '光线',
        value: lightValue.$1,
        summary: lightValue.$2,
        priority: _priority(snapshot, EnvironmentMetricType.light),
      ));
    }

    final weatherLabel = _weatherLabel(snapshot.weather);
    if (weatherLabel != null || snapshot.temperatureCelsius != null) {
      final temperature = snapshot.temperatureCelsius;
      add(EnvironmentMetricCard(
        type: EnvironmentMetricType.temperature,
        label: weatherLabel == null ? '温度' : '天气',
        value: weatherLabel == null
            ? '${temperature!.round()}°'
            : temperature == null
                ? weatherLabel
                : '$weatherLabel · ${temperature.round()}°',
        summary: snapshot.dataFreshness == ContextDataFreshness.fresh &&
                !snapshot.isStale
            ? '当前环境观测'
            : '最近一次有效观测',
        priority: _priority(snapshot, EnvironmentMetricType.temperature),
      ));
    }

    if (snapshot.precipitationMillimeters case final precipitation?) {
      add(EnvironmentMetricCard(
        type: EnvironmentMetricType.precipitation,
        label: '降水',
        value: '${precipitation.toStringAsFixed(1)} mm',
        summary: atmosphere?.precipitationProbabilityPercent == null
            ? _precipitationSummary(precipitation)
            : '未来时段概率 ${atmosphere!.precipitationProbabilityPercent!.round()}%',
        priority: _priority(snapshot, EnvironmentMetricType.precipitation),
      ));
    }

    if (snapshot.windSpeedMetersPerSecond case final wind?) {
      final direction = _windDirection(snapshot.windDirectionDegrees);
      add(EnvironmentMetricCard(
        type: EnvironmentMetricType.wind,
        label: '风',
        value: direction == null
            ? '${wind.toStringAsFixed(1)} m/s'
            : '$direction · ${wind.toStringAsFixed(1)} m/s',
        summary: atmosphere?.windGustKmh == null
            ? _windSummary(wind)
            : '阵风约 ${(atmosphere!.windGustKmh! / 3.6).toStringAsFixed(1)} m/s',
        priority: _priority(snapshot, EnvironmentMetricType.wind),
      ));
    }

    if (snapshot.visibilityKilometers case final visibility?) {
      add(EnvironmentMetricCard(
        type: EnvironmentMetricType.visibility,
        label: '能见度',
        value: _distance(visibility),
        summary: _visibilitySummary(visibility),
        priority: _priority(snapshot, EnvironmentMetricType.visibility),
      ));
    }

    final air = snapshot.airQualityCategory?.trim();
    if (!snapshot.airQualityStale && air != null && air.isNotEmpty) {
      add(EnvironmentMetricCard(
        type: EnvironmentMetricType.air,
        label: '大气',
        value: air,
        summary: snapshot.primaryPollutant == null
            ? '空气质量观测'
            : '首要污染物 ${snapshot.primaryPollutant}',
        priority: _priority(snapshot, EnvironmentMetricType.air),
      ));
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

  static (String, String)? _lightValue(
    ContextSnapshot snapshot,
    DateTime now,
  ) {
    final elevation = snapshot.solarElevationDegrees;
    final sunset = snapshot.sunset;
    final sunrise = snapshot.sunrise;
    if (elevation != null) {
      final event = sunset != null && sunset.isAfter(now)
          ? '日落 ${_time(sunset)}'
          : sunrise != null && sunrise.isAfter(now)
              ? '日出 ${_time(sunrise)}'
              : _phaseLabel(snapshot.dayPhase);
      return ('${elevation.toStringAsFixed(1)}°', event);
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
''')

# ---------------------------------------------------------------------------
# SVG icon component and gradient tokens
# ---------------------------------------------------------------------------
write('lib/src/presentation_v2/environment/v2_environment_icon.dart', r'''import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';

class V2EnvironmentIcon extends StatelessWidget {
  const V2EnvironmentIcon({
    super.key,
    required this.type,
    required this.color,
    this.size = 22,
  });

  final EnvironmentMetricType type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        _asset(type),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        semanticsLabel: _label(type),
      );

  static String _asset(EnvironmentMetricType type) => switch (type) {
        EnvironmentMetricType.cloud => 'assets/icons/environment/cloud_layers.svg',
        EnvironmentMetricType.light => 'assets/icons/environment/light.svg',
        EnvironmentMetricType.precipitation => 'assets/icons/environment/precipitation.svg',
        EnvironmentMetricType.wind => 'assets/icons/environment/wind.svg',
        EnvironmentMetricType.visibility => 'assets/icons/environment/visibility.svg',
        EnvironmentMetricType.air => 'assets/icons/environment/air.svg',
        EnvironmentMetricType.temperature => 'assets/icons/environment/temperature.svg',
      };

  static String _label(EnvironmentMetricType type) => switch (type) {
        EnvironmentMetricType.cloud => '云层',
        EnvironmentMetricType.light => '光线',
        EnvironmentMetricType.precipitation => '降水',
        EnvironmentMetricType.wind => '风',
        EnvironmentMetricType.visibility => '能见度',
        EnvironmentMetricType.air => '大气',
        EnvironmentMetricType.temperature => '天气',
      };
}
''')

write('lib/src/presentation_v2/environment/v2_environment_gradients.dart', r'''import 'package:flutter/material.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';

abstract final class V2EnvironmentGradients {
  static LinearGradient forMetric(EnvironmentMetricType type) => switch (type) {
        EnvironmentMetricType.cloud => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F8FA), Color(0xFFE7EEF3)],
          ),
        EnvironmentMetricType.light => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFF8E8), Color(0xFFF4E7CA)],
          ),
        EnvironmentMetricType.precipitation => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0F7FA), Color(0xFFDCEAF0)],
          ),
        EnvironmentMetricType.wind => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2F8F5), Color(0xFFDDECE5)],
          ),
        EnvironmentMetricType.visibility => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7FAFB), Color(0xFFE7F0F2)],
          ),
        EnvironmentMetricType.air => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F5FA), Color(0xFFE9E7F1)],
          ),
        EnvironmentMetricType.temperature => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFAF2), Color(0xFFF2E9DC)],
          ),
      };

  static Color iconColor(EnvironmentMetricType type) => switch (type) {
        EnvironmentMetricType.cloud => const Color(0xFF526F82),
        EnvironmentMetricType.light => const Color(0xFFA87525),
        EnvironmentMetricType.precipitation => const Color(0xFF3E7690),
        EnvironmentMetricType.wind => const Color(0xFF4E806C),
        EnvironmentMetricType.visibility => const Color(0xFF527887),
        EnvironmentMetricType.air => const Color(0xFF6F678A),
        EnvironmentMetricType.temperature => const Color(0xFF92704E),
      };
}
''')

# ---------------------------------------------------------------------------
# Professional cloud detail surface
# ---------------------------------------------------------------------------
write('lib/src/presentation_v2/environment/v2_cloud_detail_sheet.dart', r'''import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_gradients.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_icon.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

Future<void> showV2CloudDetailSheet(
  BuildContext context,
  CloudVisualization cloud,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .28),
      builder: (_) => V2CloudDetailSheet(cloud: cloud),
    );

class V2CloudDetailSheet extends StatelessWidget {
  const V2CloudDetailSheet({super.key, required this.cloud});

  final CloudVisualization cloud;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .86;
    return Container(
      key: const Key('v2-cloud-detail-sheet'),
      height: height,
      decoration: const BoxDecoration(
        color: V2Palette.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 14, 8),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: V2EnvironmentGradients.forMetric(
                      EnvironmentMetricType.cloud,
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: V2EnvironmentIcon(
                    type: EnvironmentMetricType.cloud,
                    color: V2EnvironmentGradients.iconColor(
                      EnvironmentMetricType.cloud,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '云层分析',
                        style: TextStyle(
                          color: V2Palette.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '当前结构、摄影影响与数据依据',
                        style: TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CloudSummary(cloud: cloud),
                  const SizedBox(height: 14),
                  _CloudStructure(cloud: cloud),
                  const SizedBox(height: 14),
                  _PhotographyImpact(cloud: cloud),
                  const SizedBox(height: 14),
                  _CloudProvenance(cloud: cloud),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudSummary extends StatelessWidget {
  const _CloudSummary({required this.cloud});
  final CloudVisualization cloud;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: V2EnvironmentGradients.forMetric(
            EnvironmentMetricType.cloud,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: V2Palette.line.withValues(alpha: .75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cloud.headline,
              key: const Key('v2-cloud-headline'),
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              cloud.summary,
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 13,
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (cloud.totalCloudCoverPercent case final total?) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${total.round()}',
                    key: const Key('v2-cloud-total'),
                    style: const TextStyle(
                      color: V2Palette.ink,
                      fontSize: 40,
                      height: .9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 3, bottom: 2),
                    child: Text(
                      '% 总云量',
                      style: TextStyle(
                        color: V2Palette.mutedInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _CloudStructure extends StatelessWidget {
  const _CloudStructure({required this.cloud});
  final CloudVisualization cloud;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(17, 17, 17, 14),
        decoration: BoxDecoration(
          color: V2Palette.paper.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: V2Palette.line.withValues(alpha: .75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '垂直云层结构',
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cloud.hasLayeredClouds
                  ? '覆盖率来自分层气象模型；不使用固定高度冒充现场云底。'
                  : '当前仅获得总云量，未补齐缺失的高、中、低云数据。',
              key: const Key('v2-cloud-layer-disclosure'),
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (cloud.hasLayeredClouds)
              SizedBox(
                key: const Key('v2-cloud-layer-chart'),
                height: 210,
                child: CustomPaint(
                  painter: _CloudLayerPainter(cloud),
                  child: const SizedBox.expand(),
                ),
              )
            else
              Container(
                height: 112,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: V2Palette.canvas.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  '分层云量暂不可用',
                  style: TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _CloudLayerPainter extends CustomPainter {
  _CloudLayerPainter(this.cloud);

  final CloudVisualization cloud;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 58.0;
    const right = 8.0;
    const top = 14.0;
    const rowHeight = 52.0;
    final width = size.width - left - right;
    final labels = <(String, double?, Color)>[
      ('高云', cloud.highCloudCoverPercent, const Color(0xFF9CB6C7)),
      ('中云', cloud.middleCloudCoverPercent, const Color(0xFF7897AA)),
      ('低云', cloud.lowCloudCoverPercent, const Color(0xFF526F82)),
    ];
    final labelStyle = const TextStyle(
      color: V2Palette.mutedInk,
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
    final valueStyle = const TextStyle(
      color: V2Palette.ink,
      fontSize: 12,
      fontWeight: FontWeight.w900,
    );

    for (var index = 0; index < labels.length; index++) {
      final item = labels[index];
      final y = top + index * rowHeight;
      final label = TextPainter(
        text: TextSpan(text: item.$1, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, y + 10));

      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y + 7, width, 26),
        const Radius.circular(13),
      );
      canvas.drawRRect(
        track,
        Paint()..color = const Color(0xFFE8EDF0),
      );
      final value = item.$2;
      if (value != null) {
        final progress = (value / 100).clamp(0.0, 1.0);
        final fillWidth = math.max(8.0, width * progress);
        final fill = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y + 7, fillWidth, 26),
          const Radius.circular(13),
        );
        canvas.drawRRect(
          fill,
          Paint()
            ..shader = LinearGradient(
              colors: [item.$3.withValues(alpha: .48), item.$3],
            ).createShader(fill.outerRect),
        );
        final text = TextPainter(
          text: TextSpan(text: '${value.round()}%', style: valueStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          Offset(size.width - right - text.width - 8, y + 11),
        );
      } else {
        final text = TextPainter(
          text: const TextSpan(text: '无数据', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          Offset(size.width - right - text.width - 8, y + 11),
        );
      }
    }

    final groundY = top + labels.length * rowHeight + 4;
    canvas.drawLine(
      Offset(left, groundY),
      Offset(size.width - right, groundY),
      Paint()
        ..color = V2Palette.line
        ..strokeWidth = 1.2,
    );
    final ground = TextPainter(
      text: const TextSpan(
        text: '地面',
        style: TextStyle(
          color: V2Palette.mutedInk,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ground.paint(canvas, Offset(0, groundY - 6));
  }

  @override
  bool shouldRepaint(covariant _CloudLayerPainter oldDelegate) =>
      oldDelegate.cloud != cloud;
}

class _PhotographyImpact extends StatelessWidget {
  const _PhotographyImpact({required this.cloud});
  final CloudVisualization cloud;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: V2Palette.paper.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: V2Palette.line.withValues(alpha: .75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '对当前拍摄的影响',
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            for (final note in cloud.photographyNotes) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(
                      color: V2Palette.moss,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      note,
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontSize: 12,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

class _CloudProvenance extends StatelessWidget {
  const _CloudProvenance({required this.cloud});
  final CloudVisualization cloud;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: V2Palette.paper.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: V2Palette.line.withValues(alpha: .65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '数据依据',
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            _row('来源', cloud.sourceLabel),
            _row('观测时间', _time(cloud.observedAt)),
            _row('有效状态', cloud.isStale ? '最近有效数据' : '当前有效'),
            if (cloud.weatherAgreement case final agreement?)
              _row('模型一致性', _agreement(agreement)),
            const SizedBox(height: 8),
            const Text(
              '云量是模型或观测对天空覆盖的描述，不等同于晚霞、日照金山或现场可见性的确定结论。',
              style: TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 10,
                height: 1.45,
              ),
            ),
          ],
        ),
      );

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.month}月${local.day}日 '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _agreement(String value) => switch (value) {
        'strong' => '较高',
        'moderate' => '一般',
        'weak' => '较低',
        'unavailable' => '不可用',
        _ => value,
      };
}
''')

# ---------------------------------------------------------------------------
# Today page integration
# ---------------------------------------------------------------------------
today_path = ROOT / 'lib/src/presentation_v2/today/v2_today_page.dart'
today = today_path.read_text(encoding='utf-8')

import_anchor = "import 'package:luma_nest/src/core/context/environment_providers.dart';\n"
imports = (
    "import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';\n"
    "import 'package:luma_nest/src/core/environment/sky_window_providers.dart';\n"
)
if imports not in today:
    today = today.replace(import_anchor, import_anchor + imports, 1)

shared_anchor = "import 'package:luma_nest/src/presentation_v2/entry/entry_card_registry.dart';\n"
new_shared = (
    "import 'package:luma_nest/src/features/today/application/environment_visualization.dart';\n"
    "import 'package:luma_nest/src/presentation_v2/environment/v2_cloud_detail_sheet.dart';\n"
    "import 'package:luma_nest/src/presentation_v2/environment/v2_environment_gradients.dart';\n"
    "import 'package:luma_nest/src/presentation_v2/environment/v2_environment_icon.dart';\n"
)
if new_shared not in today:
    today = today.replace(shared_anchor, shared_anchor + new_shared, 1)

old_content_call = '''          return _V2TodayContent(
            snapshot: value,
            composition: ref.watch(todaySurfaceCompositionProvider(value)),
'''
new_content_call = '''          final skyWindowForecast = switch (value.location) {
            final point? => ref
                .watch(
                  skyWindowForecastProvider(
                    SkyWindowRequest(
                      point: point,
                      startAt: value.observedAt,
                      hours: 24,
                    ),
                  ),
                )
                .asData
                ?.value,
            null => null,
          };
          return _V2TodayContent(
            snapshot: value,
            skyWindowForecast: skyWindowForecast,
            composition: ref.watch(todaySurfaceCompositionProvider(value)),
'''
if old_content_call not in today:
    raise SystemExit('Today content call anchor not found')
today = today.replace(old_content_call, new_content_call, 1)

constructor_old = '''  const _V2TodayContent({
    required this.snapshot,
    required this.composition,
'''
constructor_new = '''  const _V2TodayContent({
    required this.snapshot,
    required this.skyWindowForecast,
    required this.composition,
'''
if constructor_old not in today:
    raise SystemExit('Today content constructor anchor not found')
today = today.replace(constructor_old, constructor_new, 1)

field_old = '''  final ContextSnapshot snapshot;
  final SurfaceComposition composition;
'''
field_new = '''  final ContextSnapshot snapshot;
  final SkyWindowForecast? skyWindowForecast;
  final SurfaceComposition composition;
'''
if field_old not in today:
    raise SystemExit('Today content field anchor not found')
today = today.replace(field_old, field_new, 1)

conditions_old = '                  _V2CurrentConditions(snapshot: snapshot, now: now),\n'
conditions_new = '''                  _V2CurrentConditions(
                    snapshot: snapshot,
                    now: now,
                    skyWindowForecast: widget.skyWindowForecast,
                  ),
'''
if conditions_old not in today:
    raise SystemExit('Current conditions call anchor not found')
today = today.replace(conditions_old, conditions_new, 1)

class_start = today.find('class _V2CurrentConditions extends StatelessWidget {')
class_end = today.find('class _V2RegionalDiscoveryCard extends StatelessWidget {', class_start)
if class_start < 0 or class_end < 0:
    raise SystemExit('Current conditions class anchors not found')

replacement = r'''class _V2CurrentConditions extends StatelessWidget {
  const _V2CurrentConditions({
    required this.snapshot,
    required this.now,
    required this.skyWindowForecast,
  });

  final ContextSnapshot snapshot;
  final DateTime now;
  final SkyWindowForecast? skyWindowForecast;

  @override
  Widget build(BuildContext context) {
    final visualization = EnvironmentVisualization.fromSnapshot(
      snapshot,
      skyWindow: skyWindowForecast,
      now: now,
    );
    if (visualization.cards.isEmpty) return const SizedBox.shrink();
    final current =
        snapshot.dataFreshness == ContextDataFreshness.fresh &&
        !snapshot.isStale;
    return Padding(
      key: const Key('v2-current-conditions'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                current ? '此刻条件' : '最近条件',
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                ),
              ),
              const Spacer(),
              Text(
                '${_time(snapshot.observedAt)} 更新',
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 3 : 2;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final fact in visualization.cards)
                    SizedBox(
                      width: width,
                      child: _V2ConditionFact(
                        fact: fact,
                        onTap: fact.type == EnvironmentMetricType.cloud &&
                                visualization.cloud != null
                            ? () => showV2CloudDetailSheet(
                                  context,
                                  visualization.cloud!,
                                )
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';
}

class _V2ConditionFact extends StatefulWidget {
  const _V2ConditionFact({required this.fact, this.onTap});

  final EnvironmentMetricCard fact;
  final VoidCallback? onTap;

  @override
  State<_V2ConditionFact> createState() => _V2ConditionFactState();
}

class _V2ConditionFactState extends State<_V2ConditionFact> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fact = widget.fact;
    final onTap = widget.onTap;
    return Semantics(
      button: onTap != null,
      label: '${fact.label}：${fact.value}。${fact.summary}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: onTap == null ? null : (_) => setState(() => _pressed = true),
        onTapCancel: onTap == null ? null : () => setState(() => _pressed = false),
        onTapUp: onTap == null ? null : (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? .97 : 1,
          duration: const Duration(milliseconds: 140),
          child: Container(
            key: Key('v2-condition-${fact.type.name}'),
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.fromLTRB(12, 12, 11, 11),
            decoration: BoxDecoration(
              gradient: V2EnvironmentGradients.forMetric(fact.type),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: V2Palette.line.withValues(alpha: .75),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .045),
                  blurRadius: 13,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .62),
                    shape: BoxShape.circle,
                  ),
                  child: V2EnvironmentIcon(
                    type: fact.type,
                    color: V2EnvironmentGradients.iconColor(fact.type),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fact.label,
                              style: const TextStyle(
                                color: V2Palette.mutedInk,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (onTap != null)
                            const Icon(
                              CupertinoIcons.chevron_right,
                              color: V2Palette.mutedInk,
                              size: 12,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fact.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        fact.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 9.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

'''
today = today[:class_start] + replacement + today[class_end:]
today_path.write_text(today, encoding='utf-8')

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
write('test/features/today/environment_visualization_test.dart', r'''import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';

void main() {
  final now = DateTime.utc(2026, 8, 4, 10);

  test('layered cloud data enhances total cloud without inventing values', () {
    final result = EnvironmentVisualization.fromSnapshot(
      _snapshot(now, cloud: 91),
      skyWindow: _forecast(now),
      now: now,
    );

    expect(result.cloud, isNotNull);
    expect(result.cloud!.totalCloudCoverPercent, 88);
    expect(result.cloud!.lowCloudCoverPercent, 72);
    expect(result.cloud!.middleCloudCoverPercent, 46);
    expect(result.cloud!.highCloudCoverPercent, 21);
    expect(result.cloud!.hasLayeredClouds, isTrue);
    expect(result.cards.first.type, EnvironmentMetricType.cloud);
  });

  test('total-only cloud remains honest when layered data is unavailable', () {
    final result = EnvironmentVisualization.fromSnapshot(
      _snapshot(now, cloud: 64),
      now: now,
    );

    expect(result.cloud!.hasLayeredClouds, isFalse);
    expect(result.cloud!.compactLayerSummary, '总云量 64%');
    expect(result.cloud!.sourceLabel, 'Context 当前天气');
  });

  test('rain reorders actionable precipitation before cloud', () {
    final snapshot = ContextSnapshot(
      id: 'rain-order',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      primaryScene: SceneType.city,
      dayPhase: DayPhase.day,
      weather: WeatherType.rain,
      activeRoute: false,
      precipitationMillimeters: 3.2,
      cloudCoverPercent: 96,
      windSpeedMetersPerSecond: 4,
      visibilityKilometers: 9,
    );
    final result = EnvironmentVisualization.fromSnapshot(snapshot, now: now);
    expect(result.cards.first.type, EnvironmentMetricType.precipitation);
    expect(result.cards[1].type, EnvironmentMetricType.cloud);
  });
}

ContextSnapshot _snapshot(DateTime now, {double? cloud}) => ContextSnapshot(
      id: 'visualization',
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 30)),
      primaryScene: SceneType.lake,
      dayPhase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      activeRoute: false,
      cloudCoverPercent: cloud,
      windSpeedMetersPerSecond: 2.2,
      visibilityKilometers: 26,
      precipitationMillimeters: 0,
      solarElevationDegrees: 8,
    );

SkyWindowForecast _forecast(DateTime now) => SkyWindowForecast(
      algorithmVersion: 'sky-window-forecast.1',
      requestedCoordinate: const GeoPoint(latitude: 30, longitude: 120),
      requestedStartAt: now,
      endAt: now.add(const Duration(hours: 24)),
      stepMinutes: 15,
      generatedAt: now,
      expiresAt: now.add(const Duration(minutes: 15)),
      current: SkyWindowAssessment(
        observedAt: now,
        conditionBand: SkyWindowConditionBand.conditional,
        geometry: null,
        terrain: const SkyWindowTerrain(
          status: 'unavailable',
          horizonAltitudeDegrees: null,
          clearanceDegrees: null,
          obstructionDistanceKm: null,
          coverageRatio: null,
        ),
        moon: null,
        atmosphere: const SkyWindowAtmosphere(
          status: 'ready',
          conditionBand: SkyWindowConditionBand.conditional,
          totalCloudCoverPercent: 88,
          lowCloudCoverPercent: 72,
          middleCloudCoverPercent: 46,
          highCloudCoverPercent: 21,
          visibilityMeters: 26000,
          precipitationProbabilityPercent: 20,
          precipitationMm: 0,
          relativeHumidityPercent: 76,
          windSpeedKmh: 8,
          windGustKmh: 14,
        ),
        lightPollution: const SkyWindowLightPollution(
          status: 'unavailable',
          direction: null,
          p90: null,
          relativeRadianceBand: null,
          coverageRatio: null,
          dominantDirection: null,
          dominantAngularSeparationDegrees: null,
        ),
        weatherAgreement: 'strong',
        limitations: const [],
      ),
      windows: const [],
      bestWindowId: null,
      confidence: const SkyWindowConfidence(
        band: SkyWindowConfidenceBand.medium,
        criticalSourcesReady: true,
        missingSources: [],
        conflicts: [],
      ),
      calibration: const SkyBrightnessCalibration(
        status: 'unavailable',
        sampleCount: 0,
        sqmMedian: null,
        limitingMagnitudeMedian: null,
        distanceKm: null,
        limitation: null,
      ),
    );
''')

write('test/presentation_v2/environment/v2_cloud_detail_sheet_test.dart', r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_cloud_detail_sheet.dart';

void main() {
  testWidgets('cloud detail renders professional layered structure', (tester) async {
    final now = DateTime.utc(2026, 8, 4, 10);
    final cloud = CloudVisualization(
      totalCloudCoverPercent: 91,
      lowCloudCoverPercent: 82,
      middleCloudCoverPercent: 46,
      highCloudCoverPercent: 18,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      isStale: false,
      sourceLabel: 'Open-Meteo 分层云量 · 7Timer 辅助校验',
      weatherAgreement: 'strong',
      scene: SceneType.lake,
      dayPhase: DayPhase.sunset,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: V2CloudDetailSheet(cloud: cloud))),
    );

    expect(find.byKey(const Key('v2-cloud-layer-chart')), findsOneWidget);
    expect(find.byKey(const Key('v2-cloud-total')), findsOneWidget);
    expect(find.text('垂直云层结构'), findsOneWidget);
    expect(find.textContaining('低云可能遮挡'), findsOneWidget);
    expect(find.text('模型一致性'), findsOneWidget);
  });

  testWidgets('cloud detail does not fabricate missing layers', (tester) async {
    final now = DateTime.utc(2026, 8, 4, 10);
    final cloud = CloudVisualization(
      totalCloudCoverPercent: 64,
      lowCloudCoverPercent: null,
      middleCloudCoverPercent: null,
      highCloudCoverPercent: null,
      observedAt: now,
      expiresAt: now.add(const Duration(minutes: 20)),
      isStale: false,
      sourceLabel: 'Context 当前天气',
      weatherAgreement: null,
      scene: SceneType.city,
      dayPhase: DayPhase.day,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: V2CloudDetailSheet(cloud: cloud))),
    );

    expect(find.byKey(const Key('v2-cloud-layer-chart')), findsNothing);
    expect(find.text('分层云量暂不可用'), findsOneWidget);
    expect(find.textContaining('未补齐缺失'), findsOneWidget);
  });
}
''')

write('docs/environment-visualization-v1.md', '''# 环境数据可视化 V1\n\n## 首页原则\n\nToday 保持一个主机会对象，环境信息改为场景动态排序的专业摘要卡。卡片只展示当前可用事实，没有数据时不占位。雨雪优先降水，日出日落优先云层与光线，夜间优先云层与通透度。\n\n## 云层详情\n\n云层卡优先使用 Sky Window 已有的 Open-Meteo 分层云量，并保留 7Timer 一致性信息。Context 总云量作为即时与降级来源。\n\n- 有分层数据：展示高云、中云、低云覆盖率和专业结构图。\n- 只有总云量：明确显示“分层云量暂不可用”，绝不推算或补齐。\n- Sky Window 失败：不阻塞 Today、Context V5、安全链或主机会。\n- 摄影影响使用条件语气，不把云量改写成晚霞、日照金山或现场可见性的确定结论。\n\n## 视觉系统\n\n首批环境图标采用统一 24×24 圆角线性 SVG，并由 Flutter 主题色动态着色。环境卡使用低饱和语义渐变，颜色只辅助区分信息类型，不承担证据等级。\n''')

print('environment visualization V1 applied')
