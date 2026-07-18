import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

class AmbientHero extends StatelessWidget {
  const AmbientHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.windowLabel,
    this.actionLabel,
    this.onAction,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final String windowLabel;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: '$eyebrow，$title，$detail，$windowLabel',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface.withValues(alpha: .84),
                  scheme.secondaryContainer.withValues(alpha: .52),
                  scheme.surface.withValues(alpha: .72),
                ],
                stops: const [0, .56, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 20, height: 2, color: scheme.secondary),
                      const SizedBox(width: 9),
                      Text(
                        eyebrow.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    title,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      height: 1.08,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    detail,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(
                        Icons.timelapse_rounded,
                        size: 18,
                        color: scheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          windowLabel,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (actionLabel != null && onAction != null)
                        FilledButton(
                          onPressed: onAction,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: Text(actionLabel!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpportunityTimeline extends StatelessWidget {
  const OpportunityTimeline({
    super.key,
    required this.session,
    required this.now,
    this.title = '今晚时间轴',
  });

  final ShootingSession session;
  final DateTime now;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const Spacer(),
            Text(
              _trendLabel(session.trend),
              style: theme.textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 72,
          width: double.infinity,
          child: CustomPaint(
            painter: _TimelinePainter(
              session: session,
              now: now,
              scheme: theme.colorScheme,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final phase in session.phases) _PhaseLegend(phase: phase),
          ],
        ),
      ],
    );
  }

  static String _trendLabel(ShootingTrend trend) => switch (trend) {
    ShootingTrend.improving => '条件增强',
    ShootingTrend.stable => '条件稳定',
    ShootingTrend.weakening => '条件减弱',
  };
}

class _PhaseLegend extends StatelessWidget {
  const _PhaseLegend({required this.phase});
  final ShootingSessionPhase phase;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _phaseColor(context, phase.kind),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        '${_phaseLabel(phase.kind)} ${_time(phase.startsAt)}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ],
  );
}

class ConditionTrend extends StatelessWidget {
  const ConditionTrend({super.key, required this.samples});
  final List<ShootingSessionTrendSample> samples;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) return const SizedBox.shrink();
    final first = samples.first.conditionIndex;
    final last = samples.last.conditionIndex;
    final change = last - first;
    return Semantics(
      container: true,
      label:
          '环境综合条件趋势，从 $first 变化到 $last，'
          '${change >= 10
              ? '增强'
              : change <= -10
              ? '减弱'
              : '基本稳定'}。'
          '数值越高表示风、云和降水组合越适合拍摄，不是发生概率。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 142,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(
                samples: samples,
                scheme: Theme.of(context).colorScheme,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '纵轴为环境适配程度，数值越高越适合；不是发生概率。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class EquipmentReadiness extends StatelessWidget {
  const EquipmentReadiness({
    super.key,
    required this.recommended,
    required this.match,
  });

  final Set<EquipmentCapability> recommended;
  final EquipmentCapabilityMatch match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = match.isReady;
    final detail = ready
        ? '已识别 ${recommended.map(_label).join('、')}。'
        : '建议补充 ${match.missing.map(_label).join('、')}。';
    return Semantics(
      container: true,
      label: '器材准备，${ready ? '齐全' : '建议补充'}。$detail 器材不改变环境判断。',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ready
                    ? Icons.check_circle_outline_rounded
                    : Icons.backpack_outlined,
                color: ready
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '器材准备 · ${ready ? '齐全' : '建议补充'}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$detail 器材只影响出发准备，不改变环境判断。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _label(EquipmentCapability capability) => switch (capability) {
    EquipmentCapability.camera => '相机',
    EquipmentCapability.phoneCamera => '手机相机',
    EquipmentCapability.tripod => '三脚架',
    EquipmentCapability.wideAngle => '广角镜头',
    EquipmentCapability.telephoto => '长焦镜头',
    EquipmentCapability.fastLens => '大光圈镜头',
    EquipmentCapability.filter => '滤镜',
    EquipmentCapability.drone => '无人机',
    EquipmentCapability.weatherProtection => '防雨保护',
    EquipmentCapability.headlamp => '头灯',
  };
}

class DirectionCompass extends StatelessWidget {
  const DirectionCompass({
    super.key,
    required this.targetDegrees,
    this.currentDegrees,
  });

  final double targetDegrees;
  final double? currentDegrees;

  @override
  Widget build(BuildContext context) {
    final delta = currentDegrees == null
        ? null
        : _signedDelta(currentDegrees!, targetDegrees);
    return Semantics(
      label: currentDegrees == null
          ? '目标方向 ${targetDegrees.round()} 度'
          : '目标方向 ${targetDegrees.round()} 度，当前相差 ${delta!.abs().round()} 度',
      child: Row(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              painter: _CompassPainter(
                target: targetDegrees,
                current: currentDegrees,
                scheme: Theme.of(context).colorScheme,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('峰值方位', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '${_bearing(targetDegrees)}  ${targetDegrees.round()}°',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  delta == null
                      ? '罗盘不可用，仅显示目标方向'
                      : delta.abs() < 6
                      ? '朝向已对准'
                      : '向${delta > 0 ? '右' : '左'}转 ${delta.abs().round()}°',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class EvidenceDisclosure extends StatelessWidget {
  const EvidenceDisclosure({super.key, required this.factors});
  final List<ShootingSessionFactor> factors;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const Key('shooting-evidence-disclosure'),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 10),
    shape: const Border(),
    collapsedShape: const Border(),
    title: const Text('判断依据'),
    subtitle: const Text('查看支持与限制条件'),
    children: [
      for (final factor in factors)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(
                switch (factor.effect) {
                  ShootingFactorEffect.supporting => Icons.add_circle_outline,
                  ShootingFactorEffect.neutral => Icons.remove_circle_outline,
                  ShootingFactorEffect.limiting => Icons.error_outline,
                },
                size: 18,
                color: switch (factor.effect) {
                  ShootingFactorEffect.supporting => Theme.of(
                    context,
                  ).colorScheme.primary,
                  ShootingFactorEffect.neutral => Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  ShootingFactorEffect.limiting => Theme.of(
                    context,
                  ).colorScheme.tertiary,
                },
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(factor.label)),
              Text(factor.value, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
    ],
  );
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.session,
    required this.now,
    required this.scheme,
  });

  final ShootingSession session;
  final DateTime now;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 6.0;
    final right = size.width - 6;
    const lineY = 30.0;
    final total = session.endsAt.difference(session.startsAt).inMilliseconds;
    double x(DateTime value) =>
        left +
        (right - left) *
            (value.difference(session.startsAt).inMilliseconds / total).clamp(
              0,
              1,
            );
    canvas.drawLine(
      const Offset(left, lineY),
      Offset(right, lineY),
      Paint()
        ..color = scheme.outlineVariant.withValues(alpha: .7)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    for (final phase in session.phases) {
      canvas.drawLine(
        Offset(x(phase.startsAt), lineY),
        Offset(x(phase.endsAt), lineY),
        Paint()
          ..color = _phasePaintColor(scheme, phase.kind)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        Offset(x(phase.peaksAt), lineY),
        5,
        Paint()..color = scheme.surface,
      );
      canvas.drawCircle(
        Offset(x(phase.peaksAt), lineY),
        3,
        Paint()..color = _phasePaintColor(scheme, phase.kind),
      );
    }
    if (!now.isBefore(session.startsAt) && now.isBefore(session.endsAt)) {
      final nowX = x(now);
      canvas.drawLine(
        Offset(nowX, 12),
        Offset(nowX, 48),
        Paint()
          ..color = scheme.onSurface
          ..strokeWidth = 1.5,
      );
    }
    _paintText(
      canvas,
      _time(session.startsAt),
      Offset(left, 52),
      scheme.onSurfaceVariant,
    );
    final endText = _time(session.endsAt);
    _paintText(
      canvas,
      endText,
      Offset(right - endText.length * 6.2, 52),
      scheme.onSurfaceVariant,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.session != session ||
      oldDelegate.now != now ||
      oldDelegate.scheme != scheme;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.samples, required this.scheme});
  final List<ShootingSessionTrendSample> samples;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    const left = 34.0;
    const rightInset = 8.0;
    const top = 8.0;
    const bottom = 24.0;
    final right = size.width - rightInset;
    final chartBottom = size.height - bottom;
    final chartHeight = chartBottom - top;
    final startAt = samples.first.at;
    final totalMilliseconds = samples.last.at
        .difference(startAt)
        .inMilliseconds;
    for (final grid in const [
      (value: 75, label: '强'),
      (value: 50, label: '中'),
      (value: 25, label: '弱'),
    ]) {
      final y = chartBottom - chartHeight * grid.value / 100;
      _paintText(canvas, grid.label, Offset(5, y - 7), scheme.onSurfaceVariant);
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 1,
      );
    }
    double x(ShootingSessionTrendSample sample, int index) {
      if (totalMilliseconds <= 0) {
        return left + (right - left) * index / (samples.length - 1);
      }
      return left +
          (right - left) *
              sample.at.difference(startAt).inMilliseconds /
              totalMilliseconds;
    }

    final path = Path();
    for (var index = 0; index < samples.length; index += 1) {
      final point = Offset(
        x(samples[index], index),
        chartBottom - chartHeight * samples[index].conditionIndex / 100,
      );
      index == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(path)
      ..lineTo(right, chartBottom)
      ..lineTo(left, chartBottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.secondary.withValues(alpha: .28),
            scheme.secondary.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = scheme.secondary
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 0; index < samples.length; index += 1) {
      final point = Offset(
        x(samples[index], index),
        chartBottom - chartHeight * samples[index].conditionIndex / 100,
      );
      canvas.drawCircle(point, 4.5, Paint()..color = scheme.surface);
      canvas.drawCircle(point, 2.6, Paint()..color = scheme.secondary);
    }
    final timeIndexes = <int>{0, samples.length ~/ 2, samples.length - 1};
    for (final index in timeIndexes) {
      final label = _time(samples[index].at);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (x(samples[index], index) - painter.width / 2).clamp(
        left,
        right - painter.width,
      );
      painter.paint(canvas, Offset(labelX, chartBottom + 7));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.scheme != scheme;
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({
    required this.target,
    required this.current,
    required this.scheme,
  });
  final double target;
  final double? current;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = scheme.surface.withValues(alpha: .32)
        ..style = PaintingStyle.fill,
    );
    for (var degree = 0; degree < 360; degree += 15) {
      final angle = (degree - 90) * math.pi / 180;
      final major = degree % 90 == 0;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final inner =
          center +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius - (major ? 12 : 6));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = scheme.onSurface.withValues(alpha: major ? .78 : .28)
          ..strokeWidth = major ? 1.8 : 1,
      );
    }
    _needle(canvas, center, radius - 19, target, scheme.secondary, 4);
    if (current != null) {
      _needle(canvas, center, radius - 32, current!, scheme.onSurface, 1.5);
    }
    canvas.drawCircle(center, 5, Paint()..color = scheme.surface);
    canvas.drawCircle(center, 2.5, Paint()..color = scheme.secondary);
  }

  void _needle(
    Canvas canvas,
    Offset center,
    double length,
    double degrees,
    Color color,
    double width,
  ) {
    final angle = (degrees - 90) * math.pi / 180;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle), math.sin(angle)) * length,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.current != current ||
      oldDelegate.scheme != scheme;
}

Color _phaseColor(BuildContext context, ShootingPhaseKind phase) =>
    _phasePaintColor(Theme.of(context).colorScheme, phase);

Color _phasePaintColor(ColorScheme scheme, ShootingPhaseKind phase) =>
    switch (phase) {
      ShootingPhaseKind.morningBlueHour => scheme.secondary,
      ShootingPhaseKind.sunrise => scheme.tertiary,
      ShootingPhaseKind.morningMist => scheme.secondaryContainer,
      ShootingPhaseKind.reflection => scheme.primary,
      ShootingPhaseKind.warmLight => scheme.tertiary,
      ShootingPhaseKind.sunset => scheme.tertiary,
      ShootingPhaseKind.blueHour => scheme.secondary,
      ShootingPhaseKind.artificialLights => scheme.tertiary,
      ShootingPhaseKind.rainEnding => scheme.primary,
      ShootingPhaseKind.wetReflection => scheme.primary,
      ShootingPhaseKind.desertSideLight => scheme.tertiary,
      ShootingPhaseKind.texture => scheme.surfaceTint,
      ShootingPhaseKind.approach => scheme.primary,
      ShootingPhaseKind.safeStop => scheme.secondary,
      ShootingPhaseKind.shoot => scheme.tertiary,
      ShootingPhaseKind.rejoinRoute => scheme.primary,
      ShootingPhaseKind.returnWindow => scheme.secondary,
      ShootingPhaseKind.sessionEnd => scheme.outline,
    };

String _phaseLabel(ShootingPhaseKind phase) => switch (phase) {
  ShootingPhaseKind.morningBlueHour => '晨蓝',
  ShootingPhaseKind.sunrise => '日出',
  ShootingPhaseKind.morningMist => '晨雾',
  ShootingPhaseKind.reflection => '倒影',
  ShootingPhaseKind.warmLight => '暖光',
  ShootingPhaseKind.sunset => '日落',
  ShootingPhaseKind.blueHour => '蓝调',
  ShootingPhaseKind.artificialLights => '华灯初上',
  ShootingPhaseKind.rainEnding => '降水结束',
  ShootingPhaseKind.wetReflection => '湿地反光',
  ShootingPhaseKind.desertSideLight => '荒漠侧光',
  ShootingPhaseKind.texture => '地表纹理',
  ShootingPhaseKind.approach => '接近目标',
  ShootingPhaseKind.safeStop => '安全停靠',
  ShootingPhaseKind.shoot => '拍摄',
  ShootingPhaseKind.rejoinRoute => '返回路线',
  ShootingPhaseKind.returnWindow => '返程窗口',
  ShootingPhaseKind.sessionEnd => '会话结束',
};

String _time(DateTime value) =>
    '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';

String _bearing(double degrees) {
  const values = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
  return values[((degrees + 22.5) ~/ 45) % 8];
}

double _signedDelta(double current, double target) =>
    (target - current + 540) % 360 - 180;

void _paintText(Canvas canvas, String text, Offset offset, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 11,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, offset);
}
