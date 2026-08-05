import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

Future<void> showV2ProviderFactsSheet(
  BuildContext context,
  ProviderFactsBundle bundle, {
  List<ProviderSignal>? prioritizedSignals,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _V2ProviderFactsSheet(
    bundle: bundle,
    prioritizedSignals: prioritizedSignals,
  ),
);

class V2ProviderFactsSummaryCard extends StatelessWidget {
  const V2ProviderFactsSummaryCard({
    super.key,
    required this.bundle,
    required this.onTap,
    this.signals,
  });

  final ProviderFactsBundle bundle;
  final List<ProviderSignal>? signals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final signals = (this.signals ?? bundle.displayableSignals)
        .take(2)
        .toList(growable: false);
    if (signals.isEmpty) return const SizedBox.shrink();
    return V2Pressable(
      key: const Key('v2-provider-facts-summary'),
      semanticLabel: '查看环境与地区线索',
      onTap: onTap,
      color: V2Palette.skySoft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(CupertinoIcons.layers, color: V2Palette.sky, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '环境与地区线索',
                    style: TextStyle(
                      color: V2Palette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  color: V2Palette.sky,
                  size: 16,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...signals.map(
              (signal) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '• ${_displaySignalTitle(signal)}：${_displaySignalSummary(signal)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    height: 1.35,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _V2ProviderFactsSheet extends StatelessWidget {
  const _V2ProviderFactsSheet({
    required this.bundle,
    required this.prioritizedSignals,
  });

  final ProviderFactsBundle bundle;
  final List<ProviderSignal>? prioritizedSignals;

  @override
  Widget build(BuildContext context) {
    final current = prioritizedSignals ?? bundle.displayableSignals;
    return DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .42,
      maxChildSize: .94,
      expand: false,
      builder: (context, controller) => Material(
        color: V2Palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ListView(
            key: const Key('v2-provider-facts-sheet'),
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: V2Palette.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '环境与地区线索',
                      style: TextStyle(
                        color: V2Palette.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
              Text(
                '覆盖半径 ${bundle.radiusKm} 公里 · ${_time(bundle.generatedAt)} 更新。数据源相互独立，缺失不会阻断探索。',
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              if (current.isNotEmpty) ...[
                const SizedBox(height: 20),
                const _SectionTitle('当前可用线索'),
                const SizedBox(height: 8),
                ...current.map((signal) => _SignalCard(signal: signal)),
              ],
              const SizedBox(height: 18),
              const _SectionTitle('数据源状态'),
              const SizedBox(height: 8),
              ...bundle.providers.map(
                (provider) => _ProviderStateRow(provider: provider),
              ),
              const SizedBox(height: 8),
              const Text(
                '卫星目录、地图、百科和生态记录只提供观测或参考线索；道路开放、安全、活动时间和现场状态仍需官方来源或多来源复核。',
                style: TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: V2Palette.ink,
      fontSize: 15,
      fontWeight: FontWeight.w900,
    ),
  );
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal});
  final ProviderSignal signal;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: V2Palette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _categoryIcon(signal.category),
              color: V2Palette.moss,
              size: 17,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _displaySignalTitle(signal),
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              _verificationLabel(signal.verification),
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _displaySignalSummary(signal),
          style: const TextStyle(
            color: V2Palette.mutedInk,
            height: 1.45,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '观测 ${_time(signal.observedAt)} · 有效至 ${_time(signal.expiresAt)}',
          style: const TextStyle(color: V2Palette.mutedInk, fontSize: 10),
        ),
      ],
    ),
  );
}

class _ProviderStateRow extends StatelessWidget {
  const _ProviderStateRow({required this.provider});
  final ProviderFactState provider;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('v2-provider-state-${provider.id}'),
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: V2Palette.line),
    ),
    child: Row(
      children: [
        Icon(
          _statusIcon(provider.status),
          color: _statusColor(provider.status),
          size: 16,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _providerLabel(provider.id),
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (provider.source != null)
                Text(
                  provider.source!.publisher,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        Text(
          _statusLabel(provider.status),
          style: TextStyle(
            color: _statusColor(provider.status),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

bool _isEcologySignal(ProviderSignal signal) => const {
  'historicalOccurrenceInventory',
  'recentCommunityBirdSummary',
}.contains(signal.kind);

String _displaySignalTitle(ProviderSignal signal) => switch (signal.kind) {
  'historicalOccurrenceInventory' => '历史生态记录',
  'recentCommunityBirdSummary' => '近期自然观察',
  _ => signal.title,
};

String _displaySignalSummary(ProviderSignal signal) {
  if (!_isEcologySignal(signal)) return signal.summary;
  if (signal.kind == 'recentCommunityBirdSummary') {
    return '${signal.summary} 适合作为自然题材与环境理解参考。';
  }
  return '${signal.summary} 适合作为季节与区域题材参考。';
}

String _time(DateTime value) {
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}

String _verificationLabel(ProviderVerification value) => switch (value) {
  ProviderVerification.authoritative => '官方',
  ProviderVerification.observed => '观测',
  ProviderVerification.model => '模型',
  ProviderVerification.reference => '参考',
  ProviderVerification.candidate => '待核验',
};

String _statusLabel(ProviderStatus value) => switch (value) {
  ProviderStatus.ready => '可用',
  ProviderStatus.noData => '暂无数据',
  ProviderStatus.unconfigured => '未配置',
  ProviderStatus.unavailable => '暂不可用',
};

IconData _statusIcon(ProviderStatus value) => switch (value) {
  ProviderStatus.ready => CupertinoIcons.check_mark_circled_solid,
  ProviderStatus.noData => CupertinoIcons.minus_circle,
  ProviderStatus.unconfigured => CupertinoIcons.gear,
  ProviderStatus.unavailable => CupertinoIcons.exclamationmark_circle,
};

Color _statusColor(ProviderStatus value) => switch (value) {
  ProviderStatus.ready => V2Palette.moss,
  ProviderStatus.noData => V2Palette.mutedInk,
  ProviderStatus.unconfigured => V2Palette.sky,
  ProviderStatus.unavailable => V2Palette.ember,
};

IconData _categoryIcon(ProviderCategory value) => switch (value) {
  ProviderCategory.surface => Icons.satellite_alt_outlined,
  ProviderCategory.atmosphere => Icons.cloud_outlined,
  ProviderCategory.operations => Icons.campaign_outlined,
  ProviderCategory.outdoor => Icons.hiking_outlined,
  ProviderCategory.culture => Icons.account_balance_outlined,
  ProviderCategory.wildlife => Icons.nature_outlined,
  ProviderCategory.fire => Icons.local_fire_department_outlined,
  ProviderCategory.marine => Icons.waves_outlined,
  ProviderCategory.astronomy => Icons.nightlight_outlined,
  ProviderCategory.spaceWeather => Icons.auto_awesome_outlined,
  ProviderCategory.other => Icons.layers_outlined,
};

String _providerLabel(String id) => switch (id) {
  'sentinel1' => 'Sentinel-1 雷达',
  'sentinel2' => 'Sentinel-2 光学',
  'cams' => 'CAMS 大气成分',
  'aeronet' => 'NASA AERONET',
  'officialNotices' => '官方公告',
  'osm' => 'OpenStreetMap',
  'wikidata' => 'Wikidata',
  'wikimediaCommons' => 'Wikimedia Commons',
  'gbif' => 'GBIF 历史生态记录',
  'inaturalist' => 'iNaturalist 近期观察',
  'ebird' => 'eBird 近期观测（可选）',
  'firms' => 'NASA FIRMS 热异常',
  'copernicusMarine' => 'Copernicus Marine',
  'jplHorizons' => 'JPL Horizons',
  'noaaSwpc' => 'NOAA SWPC',
  _ => id,
};
