import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:luma_nest/src/features/today/application/environment_visualization.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_gradients.dart';
import 'package:luma_nest/src/presentation_v2/environment/v2_environment_icon.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

Future<void> showV2CloudDetailSheet(
  BuildContext context,
  CloudVisualization cloud,
) => showModalBottomSheet<void>(
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
      gradient: V2EnvironmentGradients.forMetric(EnvironmentMetricType.cloud),
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
      canvas.drawRRect(track, Paint()..color = const Color(0xFFE8EDF0));
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
        text.paint(canvas, Offset(size.width - right - text.width - 8, y + 11));
      } else {
        final text = TextPainter(
          text: TextSpan(text: '无数据', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(size.width - right - text.width - 8, y + 11));
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
