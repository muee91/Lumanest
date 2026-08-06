from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:120]!r}')
    target.write_text(text.replace(old, new), encoding='utf-8')


def replace_regex_once(path: str, pattern: str, replacement: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'{path}: regex anchor not found: {pattern[:120]!r}')
    target.write_text(updated, encoding='utf-8')


page = 'lib/src/presentation_v2/environment/v2_environment_workbench_page.dart'
replace_once(
    page,
    "    final samples = _forecastSamples(forecast);\n    final current =",
    "    final samples = _forecastSamples(forecast);\n    final availableMetrics = _availableTrendMetrics(samples);\n    final selectedMetric =\n        availableMetrics.isEmpty || availableMetrics.contains(_selectedMetric)\n        ? _selectedMetric\n        : availableMetrics.first;\n    final current =",
)
replace_once(
    page,
    "          current\n              ? '当前事实、候选窗口峰值与摄影影响'\n              : '最近有效事实、候选窗口峰值与摄影影响',",
    "          current\n              ? '先看结论，再决定是否值得出发'\n              : '以下结论基于最近一次有效数据',",
)
replace_once(
    page,
    "        _sectionTitle('当前环境事实', '没有数据的项目不会占位'),",
    "        _sectionTitle('当前环境事实', '只展示当前有可靠数据的项目'),",
)
replace_once(
    page,
    "        const SizedBox(height: 22),\n        _sectionTitle('未来窗口采样', '只展示当前与候选窗口峰值，不补齐中间时段'),\n        const SizedBox(height: 10),\n        _TrendMetricSelector(\n          selected: _selectedMetric,\n          onChanged: (value) => setState(() => _selectedMetric = value),\n        ),\n        const SizedBox(height: 10),\n        _WindowSampleChart(\n          metric: _selectedMetric,\n          samples: samples,\n        ),\n        const SizedBox(height: 22),\n        _sectionTitle('摄影解读', '条件语言，不把环境值改写成成功概率'),",
    "        if (availableMetrics.isNotEmpty) ...[\n          const SizedBox(height: 22),\n          _sectionTitle(\n            '未来窗口对比',\n            '只比较当前与候选窗口峰值；缺少可靠采样的指标不会显示',\n          ),\n          const SizedBox(height: 10),\n          _TrendMetricSelector(\n            metrics: availableMetrics,\n            selected: selectedMetric,\n            onChanged: (value) => setState(() => _selectedMetric = value),\n          ),\n          const SizedBox(height: 10),\n          _WindowSampleChart(metric: selectedMetric, samples: samples),\n        ],\n        const SizedBox(height: 22),\n        _sectionTitle('为什么这样判断', '只解释事实影响，不把环境条件改写成成功概率'),",
)

summary_class = r'''class _EnvironmentSummary extends StatelessWidget {
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
        color: V2Palette.night,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.viewfinder, color: V2Palette.moss),
              const SizedBox(width: 8),
              Text(
                _sceneLabel(snapshot.primaryScene),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                _freshness(snapshot),
                style: const TextStyle(
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
            style: const TextStyle(
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
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.45,
            ),
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
        style: const TextStyle(
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
        style: const TextStyle(
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
'''
replace_regex_once(
    page,
    r'class _EnvironmentSummary extends StatelessWidget \{.*?\n\}\n\nclass _FactGrid',
    summary_class + '\nclass _FactGrid',
)

selector_class = r'''class _TrendMetricSelector extends StatelessWidget {
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
              selectedColor: V2Palette.moss,
              labelStyle: TextStyle(
                color: metric == selected ? Colors.white : V2Palette.ink,
                fontWeight: FontWeight.w800,
              ),
              side: const BorderSide(color: V2Palette.line),
            ),
          ),
      ],
    ),
  );
}
'''
replace_regex_once(
    page,
    r'class _TrendMetricSelector extends StatelessWidget \{.*?\n\}\n\nclass _ForecastSample',
    selector_class + '\nclass _ForecastSample',
)
replace_once(
    page,
    "class _WindowSampleChart extends StatelessWidget {",
    "List<_TrendMetric> _availableTrendMetrics(List<_ForecastSample> samples) =>\n    List.unmodifiable(\n      _TrendMetric.values.where(\n        (metric) =>\n            samples.where((sample) => metric.read(sample.assessment) != null).length >=\n            2,\n      ),\n    );\n\nclass _WindowSampleChart extends StatelessWidget {",
)
replace_once(
    page,
    "    if (available.length < 2) {\n      return const _EmptyPanel(label: '候选窗口采样不足，暂不绘制变化图');\n    }",
    "    if (available.length < 2) return const SizedBox.shrink();",
)
replace_once(
    page,
    "            '采样点之间没有被解释为连续趋势；现场条件可能在窗口之间变化。',",
    "            '只对比当前与候选窗口峰值，不代表中间时段连续变化。',",
)
replace_once(page, "    const bottom = 34.0;", "    const bottom = 44.0;")
replace_once(
    page,
    "      _text(\n        canvas,\n        _time(samples[index].assessment.observedAt),\n        Offset(x - 16, baseline + 8),\n        9,\n        V2Palette.mutedInk,\n      );",
    "      _text(\n        canvas,\n        samples[index].label,\n        Offset(x - 12, baseline + 5),\n        8,\n        V2Palette.mutedInk,\n      );\n      _text(\n        canvas,\n        _time(samples[index].assessment.observedAt),\n        Offset(x - 16, baseline + 17),\n        9,\n        V2Palette.mutedInk,\n      );",
)

provenance_class = r'''class _ProvenanceCard extends StatelessWidget {
  const _ProvenanceCard({required this.snapshot, required this.forecast});

  final ContextSnapshot snapshot;
  final SkyWindowForecast? forecast;

  @override
  Widget build(BuildContext context) {
    final confidence = forecast?.confidence;
    final current = !snapshot.isStale &&
        snapshot.dataFreshness != ContextDataFreshness.stale;
    return Container(
      key: const Key('v2-environment-provenance'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V2Palette.paper.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: V2Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '这份判断有多可靠',
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '数据状态：${current ? '有效' : '已过期'} · 更新于 ${_dateTime(snapshot.observedAt)}',
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            forecast == null
                ? '未来窗口暂不可用，因此这里只展示当前观测。'
                : '窗口可信度：${_confidenceLabel(confidence!.band)}。依据公开天气、天文几何、地形与可用的光污染数据；7Timer 只用于交叉核对。',
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          if (confidence != null && confidence.missingSources.isNotEmpty) ...[
            const SizedBox(height: 5),
            const Text(
              '部分辅助来源未返回，系统已降低可信度，不会用缺失值补齐。',
              style: TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 5),
          const Text(
            '局地雾、临时遮挡与短时天气变化仍需在出发前确认。',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
'''
replace_regex_once(
    page,
    r'class _ProvenanceCard extends StatelessWidget \{.*?\n\}\n\nclass _EmptyPanel',
    provenance_class + '\nclass _EmptyPanel',
)

visualization = 'lib/src/features/today/application/environment_visualization.dart'
replace_once(
    visualization,
    "            sourceLabel: usableSky == null\n                ? 'Context 当前天气'\n                : 'Open-Meteo 分层云量 · 7Timer 辅助校验',",
    "            sourceLabel: usableSky == null\n                ? 'Context 当前天气'\n                : '公开天气分层云量 · 7Timer 仅作交叉核对',",
)
replace_once(
    visualization,
    "          label: '光线',",
    "          label: snapshot.solarElevationDegrees == null ? '光线时间' : '太阳高度',",
)
replace_once(
    visualization,
    "      return ('${elevation.toStringAsFixed(1)}°', event);",
    "      final position = elevation >= 0 ? '地平线上方' : '地平线下方';\n      return ('${elevation.toStringAsFixed(1)}°', '$position · $event');",
)

workbench_test = 'test/presentation_v2/environment/v2_environment_workbench_page_test.dart'
replace_once(
    workbench_test,
    "    expect(find.byKey(const Key('v2-workbench-fact-cloud')), findsOneWidget);\n    expect(tester.takeException(), isNull);",
    "    expect(find.byKey(const Key('v2-workbench-fact-cloud')), findsOneWidget);\n    expect(find.text('先看结论，再决定是否值得出发'), findsOneWidget);\n    expect(find.textContaining('值得重点关注'), findsOneWidget);\n    expect(find.text('太阳高度'), findsOneWidget);\n    expect(tester.takeException(), isNull);",
)
replace_once(
    workbench_test,
    "    expect(find.text('最近有效事实、候选窗口峰值与摄影影响'), findsOneWidget);",
    "    expect(find.text('以下结论基于最近一次有效数据'), findsOneWidget);",
)
replace_once(
    workbench_test,
    "    final emptyTrend = find.text('候选窗口采样不足，暂不绘制变化图');\n    await tester.scrollUntilVisible(\n      emptyTrend,\n      300,\n      scrollable: find.byType(Scrollable).first,\n    );\n    expect(emptyTrend, findsOneWidget);\n    expect(tester.takeException(), isNull);",
    "    expect(find.text('未来窗口对比'), findsNothing);\n    expect(find.text('候选窗口采样不足，暂不绘制变化图'), findsNothing);\n    expect(find.byKey(const Key('v2-window-sample-chart')), findsNothing);\n    expect(tester.takeException(), isNull);",
)
new_test = r'''

  testWidgets('conditional window gives a direct next action and its main limits', (
    tester,
  ) async {
    final snapshot = _snapshot();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: V2EnvironmentWorkbenchPage(
            initialSnapshot: snapshot,
            initialForecast: _conditionalForecast(snapshot),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('前后再确认一次'), findsOneWidget);
    expect(find.textContaining('云量偏多、能见度偏低'), findsOneWidget);
    expect(find.text('候选时段'), findsOneWidget);
    expect(find.text('重点时刻'), findsOneWidget);
    expect(find.textContaining('存在需要现场确认的候选窗口'), findsNothing);
    expect(tester.takeException(), isNull);
  });
'''
replace_once(
    workbench_test,
    "}\n\nContextSnapshot _snapshot()",
    new_test + "}\n\nContextSnapshot _snapshot()",
)
conditional_helper = r'''

SkyWindowForecast _conditionalForecast(ContextSnapshot snapshot) {
  final now = snapshot.observedAt;
  final current = _assessment(
    now,
    cloud: 58,
    visibilityKm: 18,
    gustKmh: 22,
  );
  final peak = _assessment(
    now.add(const Duration(hours: 2)),
    cloud: 86,
    visibilityKm: 4,
    gustKmh: 45,
  );
  final window = SkyWindowCandidate(
    id: 'conditional-window',
    startAt: peak.observedAt.subtract(const Duration(minutes: 30)),
    endAt: peak.observedAt.add(const Duration(minutes: 30)),
    peakAt: peak.observedAt,
    conditionBand: SkyWindowConditionBand.conditional,
    sampleCount: 4,
    favorableSamples: 0,
    conditionalSamples: 4,
    peakAssessment: peak,
    primaryReasons: const [],
  );
  return SkyWindowForecast(
    algorithmVersion: 'sky-window-forecast.1',
    requestedCoordinate: snapshot.location!,
    requestedStartAt: now,
    endAt: now.add(const Duration(hours: 6)),
    stepMinutes: 15,
    generatedAt: now,
    expiresAt: now.add(const Duration(minutes: 15)),
    current: current,
    windows: [window],
    bestWindowId: window.id,
    confidence: const SkyWindowConfidence(
      band: SkyWindowConfidenceBand.medium,
      criticalSourcesReady: true,
      missingSources: ['seven_timer_auxiliary'],
      conflicts: [],
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
}
'''
replace_once(
    workbench_test,
    "\nSkyWindowAssessment _assessment(",
    conditional_helper + "\nSkyWindowAssessment _assessment(",
)

visualization_test = 'test/features/today/environment_visualization_test.dart'
new_visualization_test = r'''

  test('solar elevation is named and explained without an ambiguous light value', () {
    final result = EnvironmentVisualization.fromSnapshot(
      _snapshot(now, cloud: 30),
      now: now,
    );
    final light = result.cards.firstWhere(
      (card) => card.type == EnvironmentMetricType.light,
    );

    expect(light.label, '太阳高度');
    expect(light.summary, contains('地平线上方'));
  });
'''
replace_once(
    visualization_test,
    "}\n\nContextSnapshot _snapshot",
    new_visualization_test + "}\n\nContextSnapshot _snapshot",
)
