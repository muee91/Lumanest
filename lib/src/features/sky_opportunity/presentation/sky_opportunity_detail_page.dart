import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/sky_opportunity/application/sky_opportunity_providers.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

String skyOpportunityLocation(SkyOpportunityForecast value) =>
    '/sky-opportunity/${value.eventType.name}/${value.dayOffset}';

class SkyOpportunityDetailPage extends ConsumerWidget {
  const SkyOpportunityDetailPage({
    super.key,
    required this.eventType,
    required this.dayOffset,
    this.initialForecast,
  });

  final SkyOpportunityEventType eventType;
  final int dayOffset;
  final SkyOpportunityForecast? initialForecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialForecast case final forecast?) {
      return _Detail(forecast: forecast);
    }
    final snapshot = ref.watch(environmentSnapshotProvider);
    final snapshotValue = snapshot.asData?.value;
    final location = snapshotValue?.location;
    if (location == null) {
      return _Unavailable(onBack: () => context.pop());
    }
    final daily = ref.watch(
      dailySkyOpportunitiesProvider((
        latitude: location.latitude,
        longitude: location.longitude,
        focus: skyOpportunityFocusForSnapshot(
          snapshotValue!,
          ref.watch(currentTimeProvider)(),
        ),
      )),
    );
    return daily.when(
      loading: () => const Scaffold(
        backgroundColor: V2Palette.canvas,
        body: SafeArea(child: V2LoadingObject(label: '正在核对双模型结果')),
      ),
      error: (_, _) => _Unavailable(onBack: () => context.pop()),
      data: (value) {
        final forecast = value.values
            .where(
              (item) =>
                  item.eventType == eventType && item.dayOffset == dayOffset,
            )
            .firstOrNull;
        return forecast == null
            ? _Unavailable(
                onBack: () => context.pop(),
                locationUnsupported: value.locationUnsupported,
              )
            : _Detail(forecast: forecast);
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.forecast});
  final SkyOpportunityForecast forecast;

  @override
  Widget build(BuildContext context) {
    final eventName = forecast.eventType == SkyOpportunityEventType.sunset
        ? '晚霞'
        : '朝霞';
    final datePrefix = forecast.dayOffset == 0 ? '今日' : '明日';
    return Scaffold(
      backgroundColor: V2Palette.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: V2BackButton(onTap: () => context.pop()),
              ),
              const SizedBox(height: 22),
              Text(
                '${forecast.resolvedCity} · $datePrefix$eventName',
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                forecast.label,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    _IndexObject(forecast: forecast),
                    const SizedBox(height: 14),
                    _FactRow(
                      icon: CupertinoIcons.clock,
                      label: '事件时间',
                      value: forecast.eventTime == null
                          ? '暂无可信时间'
                          : '${_time(forecast.eventTime!)} 前后',
                    ),
                    _FactRow(
                      icon: CupertinoIcons.sparkles,
                      label: '大气通透度',
                      value: forecast.clarityLabel,
                    ),
                    _FactRow(
                      icon: CupertinoIcons.arrow_2_squarepath,
                      label: '模型一致性',
                      value: '双模型判断${forecast.agreementLabel}',
                    ),
                    const SizedBox(height: 14),
                    _ModelsObject(models: forecast.models),
                    if (forecast.isStale) ...[
                      const SizedBox(height: 14),
                      const _Notice(text: '数据更新稍有延迟，可以观察，不建议据此作强结论。'),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      '${forecast.attribution}\n结果仅用于摄影创作参考',
                      style: const TextStyle(
                        color: V2Palette.mutedInk,
                        fontSize: 12,
                        height: 1.55,
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

  static String _time(DateTime value) =>
      '${value.toUtc().add(const Duration(hours: 8)).hour.toString().padLeft(2, '0')}:'
      '${value.toUtc().add(const Duration(hours: 8)).minute.toString().padLeft(2, '0')}';
}

class _IndexObject extends StatelessWidget {
  const _IndexObject({required this.forecast});
  final SkyOpportunityForecast forecast;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      boxShadow: const [
        BoxShadow(
          color: Color(0x11000000),
          blurRadius: 26,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${forecast.eventLabel}条件判断',
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          forecast.label,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 44,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          forecast.primaryReason,
          style: const TextStyle(color: V2Palette.mutedInk, height: 1.4),
        ),
      ],
    ),
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        Icon(icon, size: 20, color: V2Palette.moss),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: V2Palette.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ModelsObject extends StatelessWidget {
  const _ModelsObject({required this.models});
  final List<SkyOpportunityModelForecast> models;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F0EA),
      borderRadius: BorderRadius.circular(26),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GFS 与 EC',
          style: TextStyle(
            color: V2Palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        for (final model in models)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    model.model,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Expanded(
                  child: Text(
                    model.status == 'ok'
                        ? model.providerLabel ?? '模型结果可用'
                        : '暂不可用',
                    style: const TextStyle(color: V2Palette.mutedInk),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0DB),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(color: V2Palette.ink, height: 1.4),
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onBack, this.locationUnsupported = false});
  final VoidCallback onBack;
  final bool locationUnsupported;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: V2Palette.canvas,
    body: SafeArea(
      child: V2EmptyObject(
        icon: CupertinoIcons.cloud,
        title: locationUnsupported ? '该位置暂未覆盖晚霞预测' : '暂时无法判断朝霞晚霞',
        detail: '其他天气与安全信息仍然正常可用。',
        action: '返回',
        onAction: onBack,
      ),
    ),
  );
}
