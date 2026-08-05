import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/context/scene_context.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';
import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

class V2RegionBriefExpansionCard extends StatelessWidget {
  const V2RegionBriefExpansionCard({
    super.key,
    required this.brief,
    required this.state,
    required this.onExpand,
  });

  final RegionBrief brief;
  final RegionBriefState state;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final strongSources = brief.sources
        .where(
          (source) =>
              source.qualityTier == InsightQualityTier.s ||
              source.qualityTier == InsightQualityTier.a,
        )
        .length;
    final verifiedInsights = brief.insights
        .where(
          (insight) =>
              insight.verification == InsightVerificationState.authoritative ||
              insight.verification == InsightVerificationState.corroborated,
        )
        .length;
    final lastExpandedAt = state.lastExpandedAt;

    return Container(
      key: const Key('v2-region-brief-expansion'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: V2Palette.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: V2Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: V2Palette.mossSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  CupertinoIcons.search,
                  color: V2Palette.moss,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isExpanding ? '正在扩展探索' : '扩展探索',
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _scenePromise(brief.profile),
                      style: const TextStyle(
                        color: V2Palette.mutedInk,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.isExpanding) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 8),
            Text(
              brief.refresh.refreshingMissions.isEmpty
                  ? '正在检索审核来源并核对区域事实。'
                  : '正在处理：${brief.refresh.refreshingMissions.join('、')}',
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BriefMetricChip(label: _completenessLabel(brief.completeness)),
              _BriefMetricChip(label: '${brief.sources.length} 个来源'),
              if (strongSources > 0)
                _BriefMetricChip(label: '$strongSources 个高等级来源'),
              if (verifiedInsights > 0)
                _BriefMetricChip(label: '$verifiedInsights 条已核验'),
              if (lastExpandedAt != null)
                _BriefMetricChip(label: '上次扩展 ${_time(lastExpandedAt)}'),
            ],
          ),
          if (state.errorCode != null && !state.isExpanding) ...[
            const SizedBox(height: 12),
            Text(
              _errorCopy(state.errorCode!),
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('v2-expand-region-brief'),
              onPressed: state.isExpanding ? null : onExpand,
              icon: Icon(
                state.isExpanding
                    ? CupertinoIcons.arrow_2_circlepath
                    : CupertinoIcons.search,
                size: 17,
              ),
              label: Text(state.isExpanding ? '正在核对资料' : '主动扩展区域资料'),
              style: OutlinedButton.styleFrom(
                foregroundColor: V2Palette.moss,
                side: const BorderSide(color: V2Palette.moss),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '只在你主动触发时扩大检索范围；候选、单一来源与冲突信息会明确标记，不会伪装成已确认事实。',
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

  static String _scenePromise(ExplorationSceneProfile profile) {
    switch (profile.settlement) {
      case SettlementType.historicTown:
      case SettlementType.historicDistrict:
        return '继续核对历史脉络、建筑、街巷题材、表演、集市与地方味道。';
      case SettlementType.village:
      case SettlementType.pastoralSettlement:
        return '继续寻找村落人文、生活场景、地方物产与必要补给线索。';
      case SettlementType.metropolitan:
      case SettlementType.urbanDistrict:
        return '继续核对城市建筑、街头人文、近期活动与公共空间。';
      case SettlementType.scenicArea:
        return '继续核对景观题材、开放状态、活动安排与进入方式。';
      case SettlementType.unknown:
      case SettlementType.none:
        break;
    }
    return switch (profile.physicalScene) {
      PrimaryScene.mountain => '继续核对山体身份、观景方向、步行入口、开放状态与补给线索。',
      PrimaryScene.plateau || PrimaryScene.desert =>
        '继续核对地貌、开放道路、合法停靠、通信与补给线索。',
      PrimaryScene.inlandWater || PrimaryScene.coast || PrimaryScene.wetland =>
        '继续核对岸线题材、当地活动、进入方式与环境限制。',
      PrimaryScene.forest => '继续核对林地题材、步道入口、季节变化与开放限制。',
      _ => '继续检索人文背景、摄影题材、正在发生的活动、地方味道与实用信息。',
    };
  }

  static String _completenessLabel(RegionBriefCompleteness value) =>
      switch (value) {
        RegionBriefCompleteness.identityOnly => '基础身份',
        RegionBriefCompleteness.partial => '部分资料',
        RegionBriefCompleteness.actionable => '可行动资料',
        RegionBriefCompleteness.comprehensive => '完整简报',
      };

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _errorCopy(String code) => switch (code) {
    'location_unavailable' => '当前位置不可用，已保留现有区域资料。',
    'not_configured' => '扩展探索服务尚未配置，基础简报仍可使用。',
    _ => '本次扩展未完成，已保留现有资料，可稍后重试。',
  };
}

class V2RegionBriefInsightSections extends StatelessWidget {
  const V2RegionBriefInsightSections({
    super.key,
    required this.insights,
  });

  final List<RegionInsight> insights;

  @override
  Widget build(BuildContext context) {
    final groups = <_InsightGroup>[
      _InsightGroup(
        title: '适合拍什么',
        icon: CupertinoIcons.camera,
        items: insights.where((item) => const {
          RegionInsightType.architecture,
          RegionInsightType.naturalFeature,
          RegionInsightType.photographyTheme,
          RegionInsightType.seasonalSignal,
        }.contains(item.type)).toList(growable: false),
      ),
      _InsightGroup(
        title: '正在发生',
        icon: CupertinoIcons.calendar,
        items: insights.where((item) => const {
          RegionInsightType.event,
          RegionInsightType.performance,
          RegionInsightType.market,
        }.contains(item.type)).toList(growable: false),
      ),
      _InsightGroup(
        title: '这里的味道与人文',
        icon: CupertinoIcons.book,
        items: insights.where((item) => const {
          RegionInsightType.history,
          RegionInsightType.localStory,
          RegionInsightType.localFood,
          RegionInsightType.specialty,
          RegionInsightType.culturalPractice,
          RegionInsightType.etiquette,
        }.contains(item.type)).toList(growable: false),
      ),
      _InsightGroup(
        title: '出发前确认',
        icon: CupertinoIcons.check_mark_circled,
        items: insights.where((item) => const {
          RegionInsightType.routeStop,
          RegionInsightType.supply,
          RegionInsightType.openingStatus,
          RegionInsightType.regulation,
        }.contains(item.type)).toList(growable: false),
      ),
    ].where((group) => group.items.isNotEmpty).toList(growable: false);

    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('v2-region-brief-sections'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 18),
          _InsightGroupView(group: groups[index]),
        ],
      ],
    );
  }
}

class _InsightGroup {
  const _InsightGroup({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<RegionInsight> items;
}

class _InsightGroupView extends StatelessWidget {
  const _InsightGroupView({required this.group});

  final _InsightGroup group;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(group.icon, size: 17, color: V2Palette.moss),
          const SizedBox(width: 7),
          Text(
            group.title,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      for (final insight in group.items) _RegionInsightCard(insight: insight),
    ],
  );
}

class _RegionInsightCard extends StatelessWidget {
  const _RegionInsightCard({required this.insight});

  final RegionInsight insight;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: V2Palette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _VerificationBadge(value: insight.verification),
            if (insight.timeSensitive)
              const _BriefMetricChip(label: '时效信息'),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          insight.title,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          insight.summary,
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 13,
            height: 1.48,
          ),
        ),
      ],
    ),
  );
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.value});

  final InsightVerificationState value;

  @override
  Widget build(BuildContext context) => _BriefMetricChip(
    label: switch (value) {
      InsightVerificationState.authoritative => '官方来源',
      InsightVerificationState.corroborated => '多源核验',
      InsightVerificationState.singleSource => '单一来源',
      InsightVerificationState.candidate => '待核实',
      InsightVerificationState.conflicting => '来源冲突',
    },
  );
}

class _BriefMetricChip extends StatelessWidget {
  const _BriefMetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: V2Palette.mossSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: V2Palette.moss,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
