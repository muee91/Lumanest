import 'package:flutter/material.dart';
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
    EnvironmentMetricType.precipitation =>
      'assets/icons/environment/precipitation.svg',
    EnvironmentMetricType.wind => 'assets/icons/environment/wind.svg',
    EnvironmentMetricType.visibility =>
      'assets/icons/environment/visibility.svg',
    EnvironmentMetricType.air => 'assets/icons/environment/air.svg',
    EnvironmentMetricType.temperature =>
      'assets/icons/environment/temperature.svg',
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
