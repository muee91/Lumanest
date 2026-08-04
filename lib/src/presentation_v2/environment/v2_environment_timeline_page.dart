import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/environment/sky_window_forecast.dart';
import 'package:luma_nest/src/core/environment/sky_window_providers.dart';
import 'package:luma_nest/src/core/environment/sky_window_timeline.dart';
import 'package:luma_nest/src/core/environment/sky_window_timeline_providers.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_gradients.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_icon.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

enum EnvironmentTimelineFocus {
  overview,
  cloud,
  precipitation,
  wind,
  visibility;

  static EnvironmentTimelineFocus fromQuery(String? value) => switch (value) {
        'cloud' => cloud,
        'precipitation' => precipitation,
        'wind' => wind,
        'visibility' => visibility,
        _ => overview,
      };

  String get queryValue => name;
}

class V2EnvironmentTimelinePage extends ConsumerWidget {
  const V2EnvironmentTimelinePage({
    super.key,
    this.initialSnapshot,
    this.initialTimeline,
    this.initialFocus = EnvironmentTimelineFocus.overview,
  });

  final ContextSnapshot? initialSnapshot;
  final SkyWindowTimelineForecast? initialTimeline;
  final EnvironmentTimelineFocus initialFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialSnapshot == null && !ref.watch(environmentConsentProvider)) {
      return Scaffold(
        backgroundColor: V2Palette.canvas,
        body: SafeArea(
          child: V2EmptyObject(
            icon: CupertinoIcons.location,
            title: '需要当前位置的环境数据',
            detail: '位置只用于获取当前天气、光线和未来摄影环境，不形成服务端轨迹。',
            action: '允许位置并继续',
            onAction: () => ref.read(environmentConsentProvider.notifier).grant(),
          ),
        ),
      );
    }

    final snapshot = initialSnapshot == null
        ? ref.watch(environmentSnapshotProvider)
        : AsyncData(initialSnapshot!);
    return Scaffold(
      backgroundColor: V2Palette.canvas,
      body: SafeArea(
        child: snapshot.when(
          loading: () => const V2LoadingObject(label: '正在整理未来摄影环境'),
          error: (_, _) => V2EmptyObject(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: '环境数据暂时不可用',
            detail: '页面不会用推算值补齐缺失数据。',
            action: initialSnapshot == null ? '重新获取' : '返回',
            onAction: initialSnapshot == null
                ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
                : () => context.pop(),
          ),
          data: (value) {
            final timeline = initialTimeline ?? switch (value.location) {
                  final point? => ref
                      .watch(
                        skyWindowTimelineProvider(
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
            return _TimelineBody(
              snapshot: value,
              timeline: timeline,
              initialFocus: initialFocus,
              onRefresh: initialSnapshot == null
                  ? () => ref.read(environmentSnapshotProvider.notifier).refresh()
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _TimelineBody extends StatefulWidget {
  const _TimelineBody({
    required this.snapshot,
    required this.timeline,
    required this.initialFocus,
    required this.onRefresh,
  });

  final ContextSnapshot snapshot;
  final SkyWindowTimelineForecast? timeline;
  final EnvironmentTimelineFocus initialFocus;
  final Future<void> Function()? onRefresh;

  @override
  State<_TimelineBody> createState() => _TimelineBodyState();
}

class _TimelineBodyState extends State<_TimelineBody> {
  late EnvironmentTimelineFocus _focus = widget.initialFocus;

  @override
  void didUpdateWidget(covariant _TimelineBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFocus != widget.initialFocus) {
      _focus = widget.initialFocus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    final visualization = EnvironmentVisualization.fromSnapshot(
      widget.snapshot,
      skyWindow: timeline?.forecast,
      now: widget.snapshot.observedAt,
    );
    final list = ListView(
      key: const Key('v2-environment-timeline'),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: V2BackButton(onTap: () => context.pop()),
        ),
        const SizedBox(height: 22),
        const Text(
          '摄影环境工作台',
          style: TextStyle(
            color: V2Palette.ink,
            fontSize: 31,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          timeline == null
              ? '当前事实可用；连续预报增强暂不可用'
              : '未来 24 小时 · 每 15 分钟一个真实计算采样',
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        _SummaryCard(snapshot: widget.snapshot, timeline: timeline),
        const SizedBox(height: 18),
        if (visualization.cards.isNotEmpty) ...[
          _CurrentFacts(cards: visualization.cards),
          const SizedBox(height: 20),
        ],
        _FocusSelector(
          selected: _focus,
          onChanged: (value) => setState(() => _focus = value),
        ),
        const SizedBox(height: 12),
        if (timeline == null)
          const _EmptyTimeline()
        else
          _TimelinePanel(focus: _focus, timeline: timeline),
        const SizedBox(height: 18),
        _DataQualityCard(snapshot: widget.snapshot, timeline: timeline),
      ],
    );
    if (widget.onRefresh == null) return list;
    return RefreshIndicator(
      color: V2Palette.moss,
      onRefresh: widget.onRefresh!,
      child: list,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.snapshot, required this.timeline});

  final ContextSnapshot snapshot;
  final SkyWindowTimelineForecast? timeline;

  @override
  Widget build(BuildContext context) {
    final best = timeline?.forecast.bestWindow;
    final headline = switch (best?.conditionBand) {
      SkyWindowConditionBand.favorable => '存在条件较完整的候选窗口',
      SkyWindowConditionBand.conditional => '存在需要现场确认的候选窗口',
      _ => timeline == null ? '先看当前环境事实' : '未来窗口条件有限',
    };
    final detail = best == null
        ? '没有形成候选窗口不等同于一定不值得拍摄。'
        : '${_time(best.startAt)}–${_time(best.endAt)}，峰值 ${_time(best.peakAt)}。';
    return Container(
      key: const Key('v2-timeline-summary'),
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
                snapshot.isStale ? '最近有效数据' : '${_time(snapshot.observedAt)} 更新',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentFacts extends StatelessWidget {
  const _CurrentFacts({required this.cards});

  final List<EnvironmentMetricCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 700 ? 4 : 2;
          const gap = 8.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final card in cards.take(4))
                SizedBox(
                  width: width,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 78),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: V2EnvironmentGradients.forMetric(card.type),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: V2Palette.line),
                    ),
                    child: Row(
                      children: [
                        V2EnvironmentIcon(
                          type: card.type,
                          color: V2EnvironmentGradients.iconColor(card.type),
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                card.label,
                                style: const TextStyle(
                                  color: V2Palette.mutedInk,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                card.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: V2Palette.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class _FocusSelector extends StatelessWidget {
  const _FocusSelector({required this.selected, required this.onChanged});

  final EnvironmentTimelineFocus selected;
  final ValueChanged<EnvironmentTimelineFocus> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final focus in EnvironmentTimelineFocus.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('v2-timeline-focus-${focus.name}'),
                  label: Text(_focusLabel(focus)),
                  selected: selected == focus,
                  selectedColor: V2Palette.moss,
                  side: const BorderSide(color: V2Palette.line),
                  labelStyle: TextStyle(
                    color: selected == focus ? Colors.white : V2Palette.ink,
                    fontWeight: FontWeight.w800,
                  ),
                  onSelected: (_) => onChanged(focus),
                ),
              ),
          ],
        ),
      );
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.focus, required this.timeline});

  final EnvironmentTimelineFocus focus;
  final SkyWindowTimelineForecast timeline;

  @override
  Widget build(BuildContext context) {
    final actualFocus = focus == EnvironmentTimelineFocus.overview
        ? EnvironmentTimelineFocus.cloud
        : focus;
    final hasData = timeline.samples.any(
      (sample) => _valueFor(actualFocus, sample) != null,
    );
    if (!hasData) {
      return _MissingMetric(label: '${_focusLabel(actualFocus)}数据暂不可用');
    }
    return Container(
      key: Key('v2-timeline-chart-${actualFocus.name}'),
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 13),
      decoration: BoxDecoration(
        color: V2Palette.paper,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: V2Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _focusLabel(actualFocus),
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                _unit(actualFocus),
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Legend(focus: actualFocus),
          const SizedBox(height: 10),
          SizedBox(
            height: 238,
            child: CustomPaint(
              painter: _TimelinePainter(
                focus: actualFocus,
                samples: timeline.samples,
                windows: timeline.forecast.windows,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '每 ${timeline.forecast.stepMinutes} 分钟一个采样；数值来自公开天气预报，7Timer 仅用于一致性辅助。候选窗口不代表拍摄成功概率。',
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.focus});

  final EnvironmentTimelineFocus focus;

  @override
  Widget build(BuildContext context) {
    final items = switch (focus) {
      EnvironmentTimelineFocus.cloud => const [
          ('总云量', Color(0xFF202923)),
          ('低云', Color(0xFF4F7A5D)),
          ('中云', Color(0xFF718A99)),
          ('高云', Color(0xFFC58B57)),
        ],
      EnvironmentTimelineFocus.precipitation => const [
          ('降水概率', Color(0xFF527C98)),
          ('降水量', Color(0xFF9AB8CA)),
        ],
      EnvironmentTimelineFocus.wind => const [
          ('风速', Color(0xFF4F7A5D)),
          ('阵风', Color(0xFFB06C4F)),
        ],
      EnvironmentTimelineFocus.visibility => const [
          ('能见度', Color(0xFF527C98)),
        ],
      EnvironmentTimelineFocus.overview => const <(String, Color)>[],
    };
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 3,
                decoration: BoxDecoration(
                  color: item.$2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                item.$1,
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.focus,
    required this.samples,
    required this.windows,
  });

  final EnvironmentTimelineFocus focus;
  final List<SkyWindowTimelineSample> samples;
  final List<SkyWindowCandidate> windows;

  static const _total = Color(0xFF202923);
  static const _low = Color(0xFF4F7A5D);
  static const _middle = Color(0xFF718A99);
  static const _high = Color(0xFFC58B57);
  static const _blue = Color(0xFF527C98);
  static const _blueSoft = Color(0xFF9AB8CA);
  static const _gust = Color(0xFFB06C4F);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const top = 10.0;
    const right = 8.0;
    const bottom = 38.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    _drawWindowBands(canvas, plot);
    final maximum = _maximum();
    _drawGrid(canvas, plot, maximum);
    switch (focus) {
      case EnvironmentTimelineFocus.cloud:
        _line(canvas, plot, samples.map((e) => e.totalCloudCoverPercent).toList(), maximum, _total, 2.5);
        _line(canvas, plot, samples.map((e) => e.lowCloudCoverPercent).toList(), maximum, _low, 1.8);
        _line(canvas, plot, samples.map((e) => e.middleCloudCoverPercent).toList(), maximum, _middle, 1.8);
        _line(canvas, plot, samples.map((e) => e.highCloudCoverPercent).toList(), maximum, _high, 1.8);
      case EnvironmentTimelineFocus.precipitation:
        _bars(canvas, plot, samples.map((e) => e.precipitationMm).toList(), maximum, _blueSoft);
        _line(canvas, plot, samples.map((e) => e.precipitationProbabilityPercent).toList(), maximum, _blue, 2.3);
      case EnvironmentTimelineFocus.wind:
        _line(canvas, plot, samples.map((e) => e.windSpeedKmh).toList(), maximum, _low, 2.1);
        _line(canvas, plot, samples.map((e) => e.windGustKmh).toList(), maximum, _gust, 2.3);
      case EnvironmentTimelineFocus.visibility:
        _line(canvas, plot, samples.map((e) => e.visibilityKilometers).toList(), maximum, _blue, 2.4);
      case EnvironmentTimelineFocus.overview:
        break;
    }
    _drawTimes(canvas, plot);
  }

  double _maximum() => switch (focus) {
        EnvironmentTimelineFocus.cloud ||
        EnvironmentTimelineFocus.precipitation => 100,
        EnvironmentTimelineFocus.wind => math.max(
            20,
            _nonNull(samples.expand((e) => [e.windSpeedKmh, e.windGustKmh])) * 1.15,
          ),
        EnvironmentTimelineFocus.visibility => math.max(
            20,
            _nonNull(samples.map((e) => e.visibilityKilometers)) * 1.1,
          ),
        EnvironmentTimelineFocus.overview => 100,
      };

  double _nonNull(Iterable<double?> values) {
    final available = values.whereType<double>().toList(growable: false);
    return available.isEmpty ? 1 : available.reduce(math.max);
  }

  void _drawWindowBands(Canvas canvas, Rect plot) {
    if (windows.isEmpty || samples.length < 2) return;
    final start = samples.first.validAt.millisecondsSinceEpoch;
    final end = samples.last.validAt.millisecondsSinceEpoch;
    final span = math.max(1, end - start);
    for (final window in windows) {
      final from = ((window.startAt.millisecondsSinceEpoch - start) / span).clamp(0.0, 1.0);
      final to = ((window.endAt.millisecondsSinceEpoch - start) / span).clamp(0.0, 1.0);
      final color = window.conditionBand == SkyWindowConditionBand.favorable
          ? V2Palette.moss.withValues(alpha: .12)
          : const Color(0xFFC58B57).withValues(alpha: .10);
      canvas.drawRect(
        Rect.fromLTRB(
          plot.left + plot.width * from,
          plot.top,
          plot.left + plot.width * to,
          plot.bottom,
        ),
        Paint()..color = color,
      );
    }
  }

  void _drawGrid(Canvas canvas, Rect plot, double maximum) {
    final paint = Paint()
      ..color = V2Palette.line.withValues(alpha: .75)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index += 1) {
      final y = plot.bottom - plot.height * index / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      _text(
        canvas,
        '${(maximum * index / 4).round()}',
        Offset(0, y - 6),
        9,
        V2Palette.mutedInk,
      );
    }
  }

  void _line(
    Canvas canvas,
    Rect plot,
    List<double?> values,
    double maximum,
    Color color,
    double width,
  ) {
    Path? active;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (var index = 0; index < values.length; index += 1) {
      final value = values[index];
      if (value == null) {
        if (active != null) canvas.drawPath(active, paint);
        active = null;
        continue;
      }
      final x = values.length == 1
          ? plot.center.dx
          : plot.left + plot.width * index / (values.length - 1);
      final ratio = (value / maximum).clamp(0.0, 1.0);
      final y = plot.bottom - plot.height * ratio;
      active ??= Path()..moveTo(x, y);
      if (active.getBounds().isEmpty) {
        active.moveTo(x, y);
      } else {
        active.lineTo(x, y);
      }
    }
    if (active != null) canvas.drawPath(active, paint);
  }

  void _bars(
    Canvas canvas,
    Rect plot,
    List<double?> values,
    double maximum,
    Color color,
  ) {
    final width = math.max(1.0, plot.width / math.max(1, values.length) * .65);
    final paint = Paint()..color = color.withValues(alpha: .55);
    for (var index = 0; index < values.length; index += 1) {
      final value = values[index];
      if (value == null || value <= 0) continue;
      final x = values.length == 1
          ? plot.center.dx
          : plot.left + plot.width * index / (values.length - 1);
      final displayValue = focus == EnvironmentTimelineFocus.precipitation
          ? math.min(100, value * 20)
          : value;
      final y = plot.bottom - plot.height * (displayValue / maximum).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - width / 2, y, x + width / 2, plot.bottom),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  void _drawTimes(Canvas canvas, Rect plot) {
    if (samples.isEmpty) return;
    final count = math.min(5, samples.length);
    for (var index = 0; index < count; index += 1) {
      final sampleIndex = count == 1
          ? 0
          : ((samples.length - 1) * index / (count - 1)).round();
      final x = count == 1
          ? plot.center.dx
          : plot.left + plot.width * index / (count - 1);
      _text(
        canvas,
        _time(samples[sampleIndex].validAt),
        Offset(x - 15, plot.bottom + 10),
        9,
        V2Palette.mutedInk,
      );
    }
  }

  void _text(Canvas canvas, String text, Offset offset, double size, Color color) {
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
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.focus != focus ||
      oldDelegate.samples != samples ||
      oldDelegate.windows != windows;
}

class _DataQualityCard extends StatelessWidget {
  const _DataQualityCard({required this.snapshot, required this.timeline});

  final ContextSnapshot snapshot;
  final SkyWindowTimelineForecast? timeline;

  @override
  Widget build(BuildContext context) {
    final confidence = timeline?.forecast.confidence;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V2Palette.paper.withValues(alpha: .84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: V2Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '数据依据与限制',
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.isStale
                ? '当前事实来自最近有效缓存，已明确标记为过期。'
                : '当前事实仍在有效期内。',
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeline == null
                ? '连续时间线不可用时，Today 主机会、安全预警和当前环境事实继续独立工作。'
                : '时间线包含 ${timeline.samples.length} 个受限采样，置信等级 ${_confidenceLabel(confidence!.band)}。',
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          if (confidence != null && confidence.missingSources.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '缺失来源：${confidence.missingSources.join('、')}。',
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) => const _MissingMetric(
        label: '连续环境采样暂不可用，不会用候选窗口峰值伪装完整趋势',
      );
}

class _MissingMetric extends StatelessWidget {
  const _MissingMetric({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('v2-timeline-empty'),
        height: 150,
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: V2Palette.paper,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: V2Palette.line),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

double? _valueFor(
  EnvironmentTimelineFocus focus,
  SkyWindowTimelineSample sample,
) =>
    switch (focus) {
      EnvironmentTimelineFocus.cloud => sample.totalCloudCoverPercent,
      EnvironmentTimelineFocus.precipitation =>
        sample.precipitationProbabilityPercent ?? sample.precipitationMm,
      EnvironmentTimelineFocus.wind => sample.windGustKmh ?? sample.windSpeedKmh,
      EnvironmentTimelineFocus.visibility => sample.visibilityKilometers,
      EnvironmentTimelineFocus.overview => sample.totalCloudCoverPercent,
    };

String _focusLabel(EnvironmentTimelineFocus focus) => switch (focus) {
      EnvironmentTimelineFocus.overview => '总览',
      EnvironmentTimelineFocus.cloud => '分层云量',
      EnvironmentTimelineFocus.precipitation => '降水',
      EnvironmentTimelineFocus.wind => '风',
      EnvironmentTimelineFocus.visibility => '能见度',
    };

String _unit(EnvironmentTimelineFocus focus) => switch (focus) {
      EnvironmentTimelineFocus.overview || EnvironmentTimelineFocus.cloud => '%',
      EnvironmentTimelineFocus.precipitation => '% / mm',
      EnvironmentTimelineFocus.wind => 'km/h',
      EnvironmentTimelineFocus.visibility => 'km',
    };

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _sceneLabel(SceneType scene) => switch (scene) {
      SceneType.city => '城市',
      SceneType.lake => '湖岸',
      SceneType.mountain => '山地',
      SceneType.desert => '荒野',
      SceneType.village => '村落',
      SceneType.unknown => '当前位置',
    };

String _confidenceLabel(SkyWindowConfidenceBand band) => switch (band) {
      SkyWindowConfidenceBand.low => '低',
      SkyWindowConfidenceBand.medium => '中',
      SkyWindowConfidenceBand.high => '高',
    };
