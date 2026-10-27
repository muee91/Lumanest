import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/environment/sky_window_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_gradients.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_icon.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

class V2EnvironmentWorkbenchPage extends ConsumerWidget {
  const V2EnvironmentWorkbenchPage({
    super.key,
    this.initialSnapshot,
    this.initialForecast,
    this.embedded = false,
  });

  final ContextSnapshot? initialSnapshot;
  final SkyWindowForecast? initialForecast;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSnapshot == null && !ref.watch(environmentConsentProvider)) {
      return _surface(
        context,
        V2EmptyObject(
          icon: CupertinoIcons.location,
          title: '需要当前位置的环境数据',
          detail: '位置只用于获取当前天气、光线与摄影窗口，不形成服务端轨迹。',
          action: '允许位置并继续',
          onAction: () => ref.read(environmentConsentProvider.notifier).grant(),
        ),
      );
    }

    final snapshot = initialSnapshot == null
        ? ref.watch(environmentSnapshotProvider)
        : AsyncData(initialSnapshot!);
    return snapshot.when(
      loading: () =>
          _surface(context, const V2LoadingObject(label: '正在整理摄影环境')),
      error: (_, _) => _surface(
        context,
        V2EmptyObject(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: '环境数据暂时不可用',
          detail: '工作台不会用推算值补齐缺失数据。',
          action: initialSnapshot == null ? '重新获取' : '返回',
          onAction: initialSnapshot == null
              ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
              : () => context.pop(),
        ),
      ),
      data: (value) {
        final forecast =
            initialForecast ??
            switch (value.location) {
              final point? =>
                ref
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
        final body = _EnvironmentWorkbenchBody(
          snapshot: value,
          forecast: forecast,
          onRefresh: initialSnapshot == null
              ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
              : null,
          showBackButton: !embedded,
        );
        return embedded ? body : _surface(context, body);
      },
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    if (embedded) return child;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(child: child),
    );
  }
}

class _EnvironmentWorkbenchBody extends StatefulWidget {
  const _EnvironmentWorkbenchBody({
    required this.snapshot,
    required this.forecast,
    required this.onRefresh,
    required this.showBackButton,
  });

  final ContextSnapshot snapshot;
  final SkyWindowForecast? forecast;
  final Future<void> Function()? onRefresh;
  final bool showBackButton;

  @override
  State<_EnvironmentWorkbenchBody> createState() =>
      _EnvironmentWorkbenchBodyState();
}

class _EnvironmentWorkbenchBodyState extends State<_EnvironmentWorkbenchBody> {
  _TrendMetric _selectedMetric = _TrendMetric.cloud;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final forecast = widget.forecast;
    final visualization = EnvironmentVisualization.fromSnapshot(
      snapshot,
      skyWindow: forecast,
      now: snapshot.observedAt,
    );
    final samples = _forecastSamples(forecast);
    final availableMetrics = _availableTrendMetrics(samples);
    final selectedMetric =
        availableMetrics.isEmpty || availableMetrics.contains(_selectedMetric)
        ? _selectedMetric
        : availableMetrics.first;
    final current =
        snapshot.dataFreshness == ContextDataFreshness.fresh &&
        !snapshot.isStale;

    final content = ListView(
      key: const Key('v2-environment-workbench'),
      padding: EdgeInsets.fromLTRB(22, widget.showBackButton ? 12 : 18, 22, 34),
      children: [
        if (widget.showBackButton) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: V2BackButton(onTap: () => context.pop()),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          '摄影环境工作台',
          style: TextStyle(
            color: context.v2Ink,
            fontSize: 31,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          current ? '先看结论，再决定是否值得出发' : '以下结论基于最近一次有效数据',
          style: TextStyle(
            color: context.v2MutedInk,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        _EnvironmentSummary(
          snapshot: snapshot,
          forecast: forecast,
          visualization: visualization,
        ),
        const SizedBox(height: 18),
        _sectionTitle('当前环境事实', '只展示当前有可靠数据的项目'),
        const SizedBox(height: 10),
        _FactGrid(cards: visualization.cards),
        if (availableMetrics.isNotEmpty) ...[
          const SizedBox(height: 22),
          _sectionTitle('未来窗口对比', '只比较当前与候选窗口峰值；缺少可靠采样的指标不会显示'),
          const SizedBox(height: 10),
          _TrendMetricSelector(
            metrics: availableMetrics,
            selected: selectedMetric,
            onChanged: (value) => setState(() => _selectedMetric = value),
          ),
          const SizedBox(height: 10),
          _WindowSampleChart(metric: selectedMetric, samples: samples),
        ],
        const SizedBox(height: 22),
        _sectionTitle('为什么这样判断', '只解释事实影响，不把环境条件改写成成功概率'),
        const SizedBox(height: 10),
        for (final fact in visualization.cards) ...[
          _MetricExplanation(
            fact: fact,
            snapshot: snapshot,
            forecast: forecast,
          ),
          const SizedBox(height: 10),
        ],
        _ProvenanceCard(snapshot: snapshot, forecast: forecast),
        if (kDebugMode) ...[
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => context.push('/environment-lab'),
            icon: Icon(CupertinoIcons.lab_flask),
            label: const Text('打开环境验收实验室'),
          ),
        ],
      ],
    );

    if (widget.onRefresh == null) return content;
    return RefreshIndicator(
      color: context.v2Moss,
      onRefresh: widget.onRefresh!,
      child: content,
    );
  }

  Widget _sectionTitle(String title, String detail) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: context.v2Ink,
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        detail,
        style: TextStyle(color: context.v2MutedInk, fontSize: 11, height: 1.35),
      ),
    ],
  );
}

class _EnvironmentSummary extends StatelessWidget {
  const _EnvironmentSummary({
    required this.snapshot,
    required this.forecast,
    required this.visualization,
  });

  final ContextSnapshot snapshot;
  final SkyWindowForecast? forecast;
  final EnvironmentVisualization visualization;

  @override
  Widget build(BuildContext context) {
    final best = forecast?.bestWindow;
    final headline = _summaryHeadline(best, visualization.cards.isEmpty);
    final detail = _summaryDetail(best);
    return Container(
      key: const Key('v2-environment-summary'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.v2Night,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.viewfinder, color: context.v2Moss),
              const SizedBox(width: 8),
              Text(
                _sceneLabel(snapshot.primaryScene),
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _freshness(snapshot),
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            headline,
            key: const Key('v2-environment-summary-headline'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            detail,
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
          ),
          if (best != null) ...[
            const SizedBox(height: 17),
            Divider(color: Colors.white.withValues(alpha: .14), height: 1),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _SummaryDatum(
                    label: '候选时段',
                    value: _timeRange(best.startAt, best.endAt),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SummaryDatum(
                    label: '重点时刻',
                    value: _time(best.peakAt),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryDatum extends StatelessWidget {
  const _SummaryDatum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.25,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

String _summaryHeadline(SkyWindowCandidate? best, bool factsEmpty) {
  if (best == null) {
    return factsEmpty ? '暂时没有足够数据判断' : '先看当前环境，再决定是否出发';
  }
  return switch (best.conditionBand) {
    SkyWindowConditionBand.favorable => '${_time(best.peakAt)} 前后值得重点关注',
    SkyWindowConditionBand.conditional => '${_time(best.peakAt)} 前后再确认一次',
    _ => '暂时没有足够数据判断',
  };
}

String _summaryDetail(SkyWindowCandidate? best) {
  if (best == null) {
    return '当前没有形成可解释的候选时段；页面只保留有依据的环境事实。';
  }
  final range = _timeRange(best.startAt, best.endAt);
  if (best.conditionBand == SkyWindowConditionBand.favorable) {
    return '候选时段 $range。当前条件相对完整，但出发前仍应刷新一次。';
  }
  final cautions = _windowCautions(best.peakAssessment);
  final reason = cautions.isEmpty ? '关键条件仍不稳定' : cautions.join('、');
  return '$reason。候选时段 $range，先不要只凭这次结果直接出发。';
}

List<String> _windowCautions(SkyWindowAssessment assessment) {
  final atmosphere = assessment.atmosphere;
  final cautions = <String>[];
  final lowCloud = atmosphere.lowCloudCoverPercent;
  final totalCloud = atmosphere.totalCloudCoverPercent;
  final visibility = atmosphere.visibilityMeters;
  final precipitation = atmosphere.precipitationProbabilityPercent;
  final gust = atmosphere.windGustKmh;

  if (lowCloud != null && lowCloud >= 65) {
    cautions.add('低云可能遮挡地平线');
  } else if (totalCloud != null && totalCloud >= 75) {
    cautions.add('云量偏多');
  }
  if (visibility != null && visibility < 8000) {
    cautions.add('能见度偏低');
  }
  if (precipitation != null && precipitation >= 40) {
    cautions.add('降水可能性较高');
  }
  if (gust != null && gust >= 36) {
    cautions.add('阵风较强');
  }
  return List.unmodifiable(cautions.take(2));
}

class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.cards});

  final List<EnvironmentMetricCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const _EmptyPanel(label: '当前没有可展示的环境事实');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        const gap = 9.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: width,
                child: _FactCard(card: card),
              ),
          ],
        );
      },
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.card});

  final EnvironmentMetricCard card;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('v2-workbench-fact-${card.type.name}'),
    constraints: const BoxConstraints(minHeight: 112),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: V2EnvironmentGradients.forMetric(card.type),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.v2Line.withValues(alpha: .7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                type: card.type,
                color: V2EnvironmentGradients.iconColor(card.type),
                size: 18,
              ),
            ),
            const Spacer(),
            Text(
              card.label,
              style: TextStyle(
                color: context.v2MutedInk,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Text(
          card.value,
          style: TextStyle(
            color: context.v2Ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          card.summary,
          style: TextStyle(
            color: context.v2MutedInk,
            fontSize: 10,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

enum _TrendMetric { cloud, precipitation, wind, visibility }

extension on _TrendMetric {
  String get label => switch (this) {
    _TrendMetric.cloud => '云量',
    _TrendMetric.precipitation => '降水概率',
    _TrendMetric.wind => '阵风',
    _TrendMetric.visibility => '能见度',
  };

  String get unit => switch (this) {
    _TrendMetric.cloud || _TrendMetric.precipitation => '%',
    _TrendMetric.wind => 'km/h',
    _TrendMetric.visibility => 'km',
  };

  double? read(SkyWindowAssessment value) => switch (this) {
    _TrendMetric.cloud => value.atmosphere.totalCloudCoverPercent,
    _TrendMetric.precipitation =>
      value.atmosphere.precipitationProbabilityPercent,
    _TrendMetric.wind =>
      value.atmosphere.windGustKmh ?? value.atmosphere.windSpeedKmh,
    _TrendMetric.visibility =>
      value.atmosphere.visibilityMeters == null
          ? null
          : value.atmosphere.visibilityMeters! / 1000,
  };
}

class _TrendMetricSelector extends StatelessWidget {
  const _TrendMetricSelector({
    required this.metrics,
    required this.selected,
    required this.onChanged,
  });

  final List<_TrendMetric> metrics;
  final _TrendMetric selected;
  final ValueChanged<_TrendMetric> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final metric in metrics)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(metric.label),
              selected: metric == selected,
              onSelected: (_) => onChanged(metric),
              selectedColor: context.v2Moss,
              labelStyle: TextStyle(
                color: metric == selected ? Colors.white : context.v2Ink,
                fontWeight: FontWeight.w800,
              ),
              side: BorderSide(color: context.v2Line),
            ),
          ),
      ],
    ),
  );
}

class _ForecastSample {
  const _ForecastSample({required this.assessment, required this.label});

  final SkyWindowAssessment assessment;
  final String label;
}

List<_ForecastSample> _forecastSamples(SkyWindowForecast? forecast) {
  if (forecast == null) return const [];
  final samples = <_ForecastSample>[
    _ForecastSample(assessment: forecast.current, label: '当前'),
    for (final window in forecast.windows)
      _ForecastSample(assessment: window.peakAssessment, label: '窗口'),
  ]..sort((a, b) => a.assessment.observedAt.compareTo(b.assessment.observedAt));
  final seen = <int>{};
  return List.unmodifiable(
    samples.where(
      (sample) => seen.add(sample.assessment.observedAt.millisecondsSinceEpoch),
    ),
  );
}

List<_TrendMetric> _availableTrendMetrics(List<_ForecastSample> samples) =>
    List.unmodifiable(
      _TrendMetric.values.where(
        (metric) =>
            samples
                .where((sample) => metric.read(sample.assessment) != null)
                .length >=
            2,
      ),
    );

class _WindowSampleChart extends StatelessWidget {
  const _WindowSampleChart({required this.metric, required this.samples});

  final _TrendMetric metric;
  final List<_ForecastSample> samples;

  @override
  Widget build(BuildContext context) {
    final available = samples
        .where((sample) => metric.read(sample.assessment) != null)
        .toList(growable: false);
    if (available.length < 2) return const SizedBox.shrink();
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final chartDescription = available
        .map(
          (sample) =>
              '${sample.label} ${_time(sample.assessment.observedAt)}，'
              '${metric.read(sample.assessment)!.round()}${metric.unit}',
        )
        .join('；');
    return Container(
      key: const Key('v2-window-sample-chart'),
      padding: const EdgeInsets.fromLTRB(14, 17, 14, 12),
      decoration: BoxDecoration(
        color: context.v2Paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.v2Line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                metric.label,
                style: TextStyle(
                  color: context.v2Ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                metric.unit,
                style: TextStyle(
                  color: context.v2MutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: '${metric.label}趋势图，单位${metric.unit}。$chartDescription',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 188 + (textScale - 1) * 32,
                child: CustomPaint(
                  painter: _SampleChartPainter(
                    metric: metric,
                    samples: available,
                    textScale: textScale,
                    colors: Theme.of(context).colorScheme,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '只对比当前与候选窗口峰值，不代表中间时段连续变化。',
            style: TextStyle(
              color: context.v2MutedInk,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleChartPainter extends CustomPainter {
  _SampleChartPainter({
    required this.metric,
    required this.samples,
    required this.colors,
    this.textScale = 1,
  });

  final _TrendMetric metric;
  final List<_ForecastSample> samples;
  final ColorScheme colors;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 44.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final values = samples
        .map((sample) => metric.read(sample.assessment)!)
        .toList(growable: false);
    final fixedMaximum = switch (metric) {
      _TrendMetric.cloud || _TrendMetric.precipitation => 100.0,
      _TrendMetric.wind => math.max(20, values.reduce(math.max) * 1.15),
      _TrendMetric.visibility => math.max(20, values.reduce(math.max) * 1.1),
    };
    final gridPaint = Paint()
      ..color = colors.outlineVariant.withValues(alpha: .7)
      ..strokeWidth = 1;
    final stemPaint = Paint()
      ..color = colors.primary.withValues(alpha: .45)
      ..strokeWidth = 2;
    final pointPaint = Paint()..color = colors.primary;
    final baseline = plot.bottom;

    for (var step = 0; step <= 4; step += 1) {
      final y = plot.bottom - plot.height * step / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(
        canvas,
        '${(fixedMaximum * step / 4).round()}',
        Offset(0, y - 6),
        9 * textScale,
        colors.onSurfaceVariant,
      );
    }

    for (var index = 0; index < samples.length; index += 1) {
      final x = samples.length == 1
          ? plot.center.dx
          : plot.left + plot.width * index / (samples.length - 1);
      final ratio = (values[index] / fixedMaximum).clamp(0.0, 1.0);
      final y = baseline - plot.height * ratio;
      canvas.drawLine(Offset(x, baseline), Offset(x, y), stemPaint);
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
      _text(
        canvas,
        values[index].round().toString(),
        Offset(x - 9, y - 20),
        9 * textScale,
        colors.onSurface,
      );
      _text(
        canvas,
        samples[index].label,
        Offset(x - 12, baseline + 5),
        8 * textScale,
        colors.onSurfaceVariant,
      );
      _text(
        canvas,
        _time(samples[index].assessment.observedAt),
        Offset(x - 16, baseline + 17),
        9 * textScale,
        colors.onSurfaceVariant,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SampleChartPainter oldDelegate) =>
      oldDelegate.metric != metric ||
      oldDelegate.samples != samples ||
      oldDelegate.colors != colors ||
      oldDelegate.textScale != textScale;
}

class _MetricExplanation extends StatelessWidget {
  const _MetricExplanation({
    required this.fact,
    required this.snapshot,
    required this.forecast,
  });

  final EnvironmentMetricCard fact;
  final ContextSnapshot snapshot;
  final SkyWindowForecast? forecast;

  @override
  Widget build(BuildContext context) {
    final notes = _notes(fact.type, snapshot, forecast);
    return Container(
      key: Key('v2-metric-explanation-${fact.type.name}'),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: context.v2Paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.v2Line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V2EnvironmentIcon(
            type: fact.type,
            color: V2EnvironmentGradients.iconColor(fact.type),
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${fact.label} · ${fact.value}',
                  style: TextStyle(
                    color: context.v2Ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '· $note',
                      style: TextStyle(
                        color: context.v2MutedInk,
                        fontSize: 12,
                        height: 1.42,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _notes(
  EnvironmentMetricType type,
  ContextSnapshot snapshot,
  SkyWindowForecast? forecast,
) {
  final atmosphere = forecast?.current.atmosphere;
  return switch (type) {
    EnvironmentMetricType.cloud => [
      if (atmosphere?.lowCloudCoverPercent case final value?)
        '低云 ${value.round()}%，可能影响接近地平线的太阳或远处山体。',
      if (atmosphere?.highCloudCoverPercent case final value?)
        '高云 ${value.round()}%，可承接余晖，但不能据此断言会出现晚霞。',
      '总云量描述覆盖范围，不等同于现场光线质量。',
    ],
    EnvironmentMetricType.precipitation => [
      if (atmosphere?.precipitationProbabilityPercent case final value?)
        '候选时段降水概率 ${value.round()}%，仍需结合雷达或现场变化确认。',
      '雨后反光、低云和空气通透度可能同时改变，不能只看降水量。',
    ],
    EnvironmentMetricType.wind => [
      if (atmosphere?.windGustKmh case final value?)
        '候选时段阵风约 ${(value / 3.6).toStringAsFixed(1)} m/s。',
      '长焦、三脚架、无人机和水面倒影对阵风的容忍度不同。',
    ],
    EnvironmentMetricType.visibility => [
      '能见度影响远景层次与山体辨识，但低反差天气仍可能适合人文或局部景观。',
      if (snapshot.primaryScene == SceneType.mountain)
        '山地还要结合低云判断，能见度高不代表山峰一定无遮挡。',
    ],
    EnvironmentMetricType.light => ['太阳高度与日出日落时间只描述几何关系，现场受云层、地形和朝向共同影响。'],
    EnvironmentMetricType.temperature => ['温度用于判断体感、结露和电池状态，不直接决定画面质量。'],
    EnvironmentMetricType.air => ['空气质量会影响远景通透度与健康暴露；污染类别不等同于能见度实测。'],
  };
}

class _ProvenanceCard extends StatelessWidget {
  const _ProvenanceCard({required this.snapshot, required this.forecast});

  final ContextSnapshot snapshot;
  final SkyWindowForecast? forecast;

  @override
  Widget build(BuildContext context) {
    final confidence = forecast?.confidence;
    final current =
        !snapshot.isStale &&
        snapshot.dataFreshness != ContextDataFreshness.stale;
    return Container(
      key: const Key('v2-environment-provenance'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.v2Paper.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.v2Line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这份判断有多可靠',
            style: TextStyle(
              color: context.v2Ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '数据状态：${current ? '有效' : '已过期'} · 更新于 ${_dateTime(snapshot.observedAt)}',
            style: TextStyle(
              color: context.v2MutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            forecast == null
                ? '未来窗口暂不可用，因此这里只展示当前观测。'
                : '窗口可信度：${_confidenceLabel(confidence!.band)}。依据公开天气、天文几何、地形与可用的光污染数据；7Timer 只用于交叉核对。',
            style: TextStyle(
              color: context.v2MutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          if (confidence != null && confidence.missingSources.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '部分辅助来源未返回，系统已降低可信度，不会用缺失值补齐。',
              style: TextStyle(
                color: context.v2MutedInk,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            '局地雾、临时遮挡与短时天气变化仍需在出发前确认。',
            style: TextStyle(
              color: context.v2MutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 116,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.v2Paper,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.v2Line),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: context.v2MutedInk,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class V2EnvironmentLabPage extends StatefulWidget {
  const V2EnvironmentLabPage({super.key});

  @override
  State<V2EnvironmentLabPage> createState() => _V2EnvironmentLabPageState();
}

class _V2EnvironmentLabPageState extends State<V2EnvironmentLabPage> {
  String _fixture = 'citySunset';
  double _deviceWidth = 390;
  double _textScale = 1;

  late final Map<String, _EnvironmentFixture> _fixtures = {
    'citySunset': _fixtureData(
      label: '城市落日',
      scene: SceneType.city,
      phase: DayPhase.sunset,
      weather: WeatherType.cloudy,
      cloud: 54,
      low: 18,
      middle: 35,
      high: 62,
      visibility: 18,
      wind: 4.2,
      gust: 24,
      precipitation: 0,
      probability: 10,
    ),
    'mountainLowCloud': _fixtureData(
      label: '山地低云',
      scene: SceneType.mountain,
      phase: DayPhase.dawn,
      weather: WeatherType.cloudy,
      cloud: 82,
      low: 76,
      middle: 42,
      high: 20,
      visibility: 6,
      wind: 7.5,
      gust: 41,
      precipitation: .1,
      probability: 35,
    ),
    'lakeRain': _fixtureData(
      label: '湖岸降雨',
      scene: SceneType.lake,
      phase: DayPhase.day,
      weather: WeatherType.rain,
      cloud: 94,
      low: 88,
      middle: 76,
      high: 45,
      visibility: 3.5,
      wind: 9.2,
      gust: 52,
      precipitation: 4.8,
      probability: 85,
    ),
    'clearNight': _fixtureData(
      label: '晴朗夜间',
      scene: SceneType.desert,
      phase: DayPhase.night,
      weather: WeatherType.clear,
      cloud: 8,
      low: 3,
      middle: 2,
      high: 7,
      visibility: 42,
      wind: 2.4,
      gust: 12,
      precipitation: 0,
      probability: 0,
    ),
    'stalePartial': _fixtureData(
      label: '过期且缺失',
      scene: SceneType.village,
      phase: DayPhase.blueHour,
      weather: WeatherType.unknown,
      cloud: null,
      low: null,
      middle: null,
      high: null,
      visibility: null,
      wind: null,
      gust: null,
      precipitation: null,
      probability: null,
      stale: true,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final fixture = _fixtures[_fixture]!;
    return Scaffold(
      backgroundColor: const Color(0xFFE7E7E2),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => context.pop(),
                    icon: Icon(CupertinoIcons.back),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '环境验收实验室',
                          style: TextStyle(
                            color: context.v2Ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '场景、宽度和字体缩放即时检查',
                          style: TextStyle(
                            color: context.v2MutedInk,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DropdownButton<String>(
                    value: _fixture,
                    items: [
                      for (final entry in _fixtures.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value.label),
                        ),
                    ],
                    onChanged: (value) => setState(() => _fixture = value!),
                  ),
                  DropdownButton<double>(
                    value: _deviceWidth,
                    items: const [
                      DropdownMenuItem(value: 320.0, child: Text('320px')),
                      DropdownMenuItem(value: 390.0, child: Text('390px')),
                      DropdownMenuItem(value: 768.0, child: Text('768px')),
                    ],
                    onChanged: (value) => setState(() => _deviceWidth = value!),
                  ),
                  DropdownButton<double>(
                    value: _textScale,
                    items: const [
                      DropdownMenuItem(value: 1.0, child: Text('文字 100%')),
                      DropdownMenuItem(value: 1.15, child: Text('文字 115%')),
                      DropdownMenuItem(value: 1.3, child: Text('文字 130%')),
                    ],
                    onChanged: (value) => setState(() => _textScale = value!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(
                    MediaQuery.sizeOf(context).width,
                    _deviceWidth,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      key: const Key('v2-environment-lab-device'),
                      width: _deviceWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: context.v2Canvas,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .16),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(_textScale)),
                        child: ProviderScope(
                          child: V2EnvironmentWorkbenchPage(
                            initialSnapshot: fixture.snapshot,
                            initialForecast: fixture.forecast,
                            embedded: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvironmentFixture {
  const _EnvironmentFixture({
    required this.label,
    required this.snapshot,
    required this.forecast,
  });

  final String label;
  final ContextSnapshot snapshot;
  final SkyWindowForecast forecast;
}

_EnvironmentFixture _fixtureData({
  required String label,
  required SceneType scene,
  required DayPhase phase,
  required WeatherType weather,
  required double? cloud,
  required double? low,
  required double? middle,
  required double? high,
  required double? visibility,
  required double? wind,
  required double? gust,
  required double? precipitation,
  required double? probability,
  bool stale = false,
}) {
  final now = DateTime.utc(2026, 8, 4, 10);
  final snapshot = ContextSnapshot(
    id: 'environment-lab-$label',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 15)),
    primaryScene: scene,
    dayPhase: phase,
    weather: weather,
    activeRoute: false,
    location: const GeoPoint(latitude: 30.27, longitude: 120.15),
    temperatureCelsius: weather == WeatherType.snow ? -2 : 24,
    windSpeedMetersPerSecond: wind,
    windDirectionDegrees: 230,
    visibilityKilometers: visibility,
    precipitationMillimeters: precipitation,
    cloudCoverPercent: cloud,
    airQualityIndex: 48,
    airQualityCategory: '优',
    primaryPollutant: null,
    airQualityObservedAt: now,
    airQualityStale: stale,
    solarElevationDegrees: phase == DayPhase.night ? -24 : 5.5,
    sunrise: now.subtract(const Duration(hours: 3)),
    sunset: now.add(const Duration(hours: 2)),
    isStale: stale,
    dataFreshness: stale
        ? ContextDataFreshness.stale
        : ContextDataFreshness.fresh,
  );
  final assessments = List.generate(5, (index) {
    final factor = index / 4;
    return _fixtureAssessment(
      at: now.add(Duration(hours: index * 2)),
      cloud: cloud == null
          ? null
          : (cloud + (index.isEven ? 6 : -8)).clamp(0, 100).toDouble(),
      low: low,
      middle: middle,
      high: high,
      visibility: visibility == null
          ? null
          : math.max(1, visibility + (factor - .5) * 8).toDouble() * 1000,
      windKmh: wind == null ? null : wind * 3.6 + index * 2,
      gustKmh: gust,
      precipitation: precipitation,
      probability: probability,
      condition: weather == WeatherType.rain
          ? SkyWindowConditionBand.unavailable
          : index == 3
          ? SkyWindowConditionBand.favorable
          : SkyWindowConditionBand.conditional,
    );
  });
  final windows = <SkyWindowCandidate>[
    for (var index = 1; index < assessments.length; index += 1)
      if (assessments[index].conditionBand ==
              SkyWindowConditionBand.favorable ||
          assessments[index].conditionBand ==
              SkyWindowConditionBand.conditional)
        SkyWindowCandidate(
          id: 'lab-window-$index',
          startAt: assessments[index].observedAt.subtract(
            const Duration(minutes: 30),
          ),
          endAt: assessments[index].observedAt.add(const Duration(minutes: 30)),
          peakAt: assessments[index].observedAt,
          conditionBand: assessments[index].conditionBand,
          sampleCount: 4,
          favorableSamples:
              assessments[index].conditionBand ==
                  SkyWindowConditionBand.favorable
              ? 4
              : 0,
          conditionalSamples:
              assessments[index].conditionBand ==
                  SkyWindowConditionBand.conditional
              ? 4
              : 0,
          peakAssessment: assessments[index],
          primaryReasons: const [],
        ),
  ];
  final forecast = SkyWindowForecast(
    algorithmVersion: 'sky-window-forecast.1',
    requestedCoordinate: const GeoPoint(latitude: 30.27, longitude: 120.15),
    requestedStartAt: now,
    endAt: now.add(const Duration(hours: 8)),
    stepMinutes: 15,
    generatedAt: now,
    expiresAt: now.add(const Duration(minutes: 15)),
    current: assessments.first,
    windows: windows,
    bestWindowId: windows.isEmpty ? null : windows.last.id,
    confidence: SkyWindowConfidence(
      band: stale
          ? SkyWindowConfidenceBand.low
          : SkyWindowConfidenceBand.medium,
      criticalSourcesReady: !stale,
      missingSources: stale
          ? const ['open_meteo_weather']
          : const ['seven_timer_auxiliary'],
      conflicts: const [],
    ),
    calibration: const SkyBrightnessCalibration(
      status: 'unconfigured',
      sampleCount: 0,
      sqmMedian: null,
      limitingMagnitudeMedian: null,
      distanceKm: null,
      limitation: null,
    ),
  );
  return _EnvironmentFixture(
    label: label,
    snapshot: snapshot,
    forecast: forecast,
  );
}

SkyWindowAssessment _fixtureAssessment({
  required DateTime at,
  required double? cloud,
  required double? low,
  required double? middle,
  required double? high,
  required double? visibility,
  required double? windKmh,
  required double? gustKmh,
  required double? precipitation,
  required double? probability,
  required SkyWindowConditionBand condition,
}) => SkyWindowAssessment(
  observedAt: at,
  conditionBand: condition,
  geometry: null,
  terrain: const SkyWindowTerrain(
    status: 'unavailable',
    horizonAltitudeDegrees: null,
    clearanceDegrees: null,
    obstructionDistanceKm: null,
    coverageRatio: null,
  ),
  moon: null,
  atmosphere: SkyWindowAtmosphere(
    status: cloud == null ? 'unavailable' : 'ready',
    conditionBand: condition,
    totalCloudCoverPercent: cloud,
    lowCloudCoverPercent: low,
    middleCloudCoverPercent: middle,
    highCloudCoverPercent: high,
    visibilityMeters: visibility,
    precipitationProbabilityPercent: probability,
    precipitationMm: precipitation,
    relativeHumidityPercent: 68,
    windSpeedKmh: windKmh,
    windGustKmh: gustKmh,
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
  weatherAgreement: 'unavailable',
  limitations: const [],
);

String _sceneLabel(SceneType value) => switch (value) {
  SceneType.city => '城市环境',
  SceneType.lake => '湖岸环境',
  SceneType.mountain => '山地环境',
  SceneType.desert => '荒野环境',
  SceneType.village => '村镇环境',
  SceneType.unknown => '当前环境',
};

String _freshness(ContextSnapshot snapshot) =>
    snapshot.isStale || snapshot.dataFreshness == ContextDataFreshness.stale
    ? '最近有效数据'
    : '当前有效数据';

String _confidenceLabel(SkyWindowConfidenceBand value) => switch (value) {
  SkyWindowConfidenceBand.low => '低',
  SkyWindowConfidenceBand.medium => '中',
  SkyWindowConfidenceBand.high => '高',
};

String _time(DateTime value) =>
    '${value.toLocal().hour.toString().padLeft(2, '0')}:'
    '${value.toLocal().minute.toString().padLeft(2, '0')}';

String _timeRange(DateTime start, DateTime end) =>
    '${_time(start)}–${_time(end)}';

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.month}月${local.day}日 ${_time(local)}';
}
