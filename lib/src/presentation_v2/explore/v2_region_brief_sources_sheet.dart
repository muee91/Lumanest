import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

Future<void> showV2RegionBriefSourcesSheet(
  BuildContext context,
  List<InsightEvidence> sources,
) async {
  final ordered = [...sources]
    ..sort((left, right) {
      final tier = _tierRank(
        left.qualityTier,
      ).compareTo(_tierRank(right.qualityTier));
      if (tier != 0) return tier;
      return right.observedAt.compareTo(left.observedAt);
    });
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: .78,
      child: Container(
        key: const Key('v2-region-brief-sources-sheet'),
        decoration: BoxDecoration(
          color: context.v2Canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: context.v2Line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '区域资料依据',
                            style: TextStyle(
                              color: context.v2Ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '按来源等级与采集时间排序',
                            style: TextStyle(
                              color: context.v2MutedInk,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(CupertinoIcons.xmark_circle_fill),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  '来源证明资料从哪里取得，不自动证明地点当前开放、安全或可达；管制与安全结论仍以独立官方链为准。',
                  style: TextStyle(
                    color: context.v2MutedInk,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
              Expanded(
                child: ordered.isEmpty
                    ? Center(
                        child: Text(
                          '当前简报没有可展示的资料依据',
                          style: TextStyle(color: context.v2MutedInk),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        itemCount: ordered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _RegionBriefSourceCard(source: ordered[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RegionBriefSourceCard extends StatelessWidget {
  const _RegionBriefSourceCard({required this.source});

  final InsightEvidence source;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.v2Paper,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.v2Line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 7,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _SourceTierBadge(tier: source.qualityTier),
            Text(
              source.publisher,
              style: TextStyle(
                color: context.v2Moss,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          source.title,
          style: TextStyle(
            color: context.v2Ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${source.url.host} · 采集于 ${_dateTime(source.observedAt)}',
          style: TextStyle(
            color: context.v2MutedInk,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '策略 ${source.sourcePolicyId} · 版本 ${source.version}',
          style: TextStyle(
            color: context.v2MutedInk,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _SourceTierBadge extends StatelessWidget {
  const _SourceTierBadge({required this.tier});

  final InsightQualityTier tier;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: context.v2MossSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      switch (tier) {
        InsightQualityTier.s => 'S · 权威来源',
        InsightQualityTier.a => 'A · 高质量来源',
        InsightQualityTier.b => 'B · 审核参考',
        InsightQualityTier.c => 'C · 辅助参考',
      },
      style: TextStyle(
        color: context.v2Moss,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

int _tierRank(InsightQualityTier value) => switch (value) {
  InsightQualityTier.s => 0,
  InsightQualityTier.a => 1,
  InsightQualityTier.b => 2,
  InsightQualityTier.c => 3,
};

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
