import 'package:flutter/material.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_surface.dart';

class RouteWeatherStrip extends StatelessWidget {
  const RouteWeatherStrip({super.key, required this.report});

  final RouteWeatherReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partial = report.coverage == RouteWeatherCoverage.partial;
    return LumaNestSurface(
      tone: LumaNestSurfaceTone.solid,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.route_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('沿途逐点天气', style: theme.textTheme.titleMedium),
              ),
              Text(
                partial ? '部分可用' : '逐点预报',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: partial
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '按预计到达时刻查询 · ${_sourceLabel(report.source)}${report.hasStaleSamples ? ' · 含缓存数据' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: LumaNestSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < report.samples.length; index++) ...[
                  _RouteWeatherPoint(sample: report.samples[index]),
                  if (index != report.samples.length - 1)
                    Container(
                      width: 28,
                      height: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(String source) =>
      source == 'QWeather' ? '和风天气' : source;
}

class _RouteWeatherPoint extends StatelessWidget {
  const _RouteWeatherPoint({required this.sample});

  final RouteWeatherSample sample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon(sample), size: 18),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(sample.progress * 100).round()}%',
                    style: theme.textTheme.labelLarge,
                  ),
                  Text(
                    _time(sample.expectedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_condition(sample), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            _metrics(sample),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(RouteWeatherSample sample) {
    if (sample.thunder) return Icons.thunderstorm_outlined;
    return switch (sample.condition) {
      RouteWeatherCondition.clear => Icons.wb_sunny_outlined,
      RouteWeatherCondition.cloudy => Icons.cloud_outlined,
      RouteWeatherCondition.rain => Icons.water_drop_outlined,
      RouteWeatherCondition.snow => Icons.ac_unit_outlined,
      RouteWeatherCondition.dust => Icons.air_outlined,
      RouteWeatherCondition.unknown => Icons.cloud_queue_outlined,
    };
  }

  static String _condition(RouteWeatherSample sample) {
    if (sample.thunder) return '雷雨风险';
    return switch (sample.condition) {
      RouteWeatherCondition.clear => '晴朗',
      RouteWeatherCondition.cloudy => '多云',
      RouteWeatherCondition.rain => '降雨',
      RouteWeatherCondition.snow => '降雪',
      RouteWeatherCondition.dust => '沙尘',
      RouteWeatherCondition.unknown => '天气未知',
    };
  }

  static String _metrics(RouteWeatherSample sample) {
    final wind = '风 ${sample.windSpeedMps.toStringAsFixed(1)}m/s';
    final rain = sample.precipitationMm > 0
        ? '雨 ${sample.precipitationMm.toStringAsFixed(1)}mm'
        : '无降水';
    return '$wind · $rain';
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
