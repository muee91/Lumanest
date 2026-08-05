from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:120]!r}')
    target.write_text(text.replace(old, new), encoding='utf-8')


# Policy: scope verification to weak, time-sensitive or conflicting evidence.
Path('lib/src/features/explore/application/region_brief_request_policy.dart').write_text(r'''import 'package:luma_nest/src/features/explore/domain/exploration_scene_profile.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

class RegionBriefRequestPlan {
  const RegionBriefRequestPlan({
    required this.activationType,
    required this.radiusMeters,
    required this.requestedSections,
    required this.expanded,
  });

  final String activationType;
  final int radiusMeters;
  final List<String> requestedSections;
  final bool expanded;
}

abstract final class RegionBriefRequestPolicy {
  static const automaticSections = <String>[
    'identity',
    'orientation',
    'photoThemes',
    'practical',
  ];

  static const expandedSections = <String>[
    'identity',
    'orientation',
    'photoThemes',
    'happeningNow',
    'places',
    'localTaste',
    'etiquette',
    'practical',
  ];

  static const _verificationPriority = <String>[
    'practical',
    'happeningNow',
    'places',
    'photoThemes',
    'localTaste',
    'etiquette',
    'identity',
    'orientation',
  ];

  static RegionBriefRequestPlan plan(
    ExplorationSceneProfile profile, {
    required bool manual,
  }) => RegionBriefRequestPlan(
    activationType: manual ? 'user_manual' : 'foreground_opportunistic',
    radiusMeters: radiusFor(profile, expanded: manual),
    requestedSections: manual ? expandedSections : automaticSections,
    expanded: manual,
  );

  static RegionBriefRequestPlan verificationPlan(
    ExplorationSceneProfile profile,
    RegionBrief brief,
  ) => RegionBriefRequestPlan(
    activationType: 'ai_verification',
    radiusMeters: _verificationRadius(profile),
    requestedSections: verificationSections(brief),
    expanded: false,
  );

  static int radiusFor(
    ExplorationSceneProfile profile, {
    required bool expanded,
  }) {
    if (profile.remoteness == RemotenessLevel.remote ||
        profile.remoteness == RemotenessLevel.extreme) {
      return 50000;
    }
    if (profile.mobility.name == 'driving') {
      return expanded ? 35000 : 20000;
    }
    if (!expanded) return 5000;
    return switch (profile.settlement) {
      SettlementType.historicTown ||
      SettlementType.historicDistrict ||
      SettlementType.village => 15000,
      SettlementType.scenicArea => 20000,
      _ => 12000,
    };
  }

  static bool needsVerification(RegionBrief? brief) =>
      brief != null && verificationSections(brief).isNotEmpty;

  static int verificationTargetCount(RegionBrief? brief) {
    if (brief == null) return 0;
    return brief.insights.where(_needsVerification).length;
  }

  static List<String> verificationSections(RegionBrief brief) {
    final requested = <String>{};
    for (final insight in brief.insights.where(_needsVerification)) {
      requested.add(_sectionFor(insight.type));
    }
    return _verificationPriority
        .where(requested.contains)
        .take(4)
        .toList(growable: false);
  }

  /// Pending or unavailable refreshes never erase a usable brief for the same
  /// region. A lightweight foreground refresh also cannot downgrade a richer
  /// manual result. Verification is adopted only when it reduces evidence
  /// debt without deleting facts or sources.
  static bool shouldKeepPrevious({
    required RegionBrief? previous,
    required RegionBrief incoming,
    required bool manual,
    bool verification = false,
  }) {
    if (previous == null || previous.regionId != incoming.regionId) return false;
    if (previous.hasUsableFacts && !incoming.hasUsableFacts) return true;
    if (verification) return !_verificationImproved(previous, incoming);
    if (manual) return false;
    final previousRank = _completenessRank(previous.completeness);
    final incomingRank = _completenessRank(incoming.completeness);
    if (previousRank != incomingRank) return previousRank > incomingRank;
    final previousEvidence = _evidenceWeight(previous);
    final incomingEvidence = _evidenceWeight(incoming);
    return previousEvidence > incomingEvidence;
  }

  static bool _verificationImproved(
    RegionBrief previous,
    RegionBrief incoming,
  ) {
    if (!incoming.hasUsableFacts ||
        _completenessRank(incoming.completeness) <
            _completenessRank(previous.completeness) ||
        incoming.insights.length < previous.insights.length ||
        incoming.sources.length < previous.sources.length) {
      return false;
    }
    final previousDebt = _verificationDebt(previous);
    final incomingDebt = _verificationDebt(incoming);
    if (incomingDebt < previousDebt) return true;
    return incomingDebt == previousDebt &&
        _evidenceWeight(incoming) > _evidenceWeight(previous);
  }

  static bool _needsVerification(RegionInsight insight) =>
      insight.verification == InsightVerificationState.candidate ||
      insight.verification == InsightVerificationState.conflicting ||
      insight.timeSensitive &&
          insight.verification == InsightVerificationState.singleSource;

  static int _verificationRadius(ExplorationSceneProfile profile) {
    if (profile.remoteness == RemotenessLevel.remote ||
        profile.remoteness == RemotenessLevel.extreme) {
      return 50000;
    }
    if (profile.mobility.name == 'driving') return 25000;
    return switch (profile.settlement) {
      SettlementType.historicTown ||
      SettlementType.historicDistrict ||
      SettlementType.village => 15000,
      SettlementType.scenicArea => 20000,
      _ => 12000,
    };
  }

  static String _sectionFor(RegionInsightType type) => switch (type) {
    RegionInsightType.areaIdentity ||
    RegionInsightType.history ||
    RegionInsightType.localStory => 'identity',
    RegionInsightType.orientation => 'orientation',
    RegionInsightType.architecture ||
    RegionInsightType.naturalFeature ||
    RegionInsightType.photographyTheme ||
    RegionInsightType.seasonalSignal => 'photoThemes',
    RegionInsightType.performance ||
    RegionInsightType.event ||
    RegionInsightType.market => 'happeningNow',
    RegionInsightType.routeStop => 'places',
    RegionInsightType.localFood || RegionInsightType.specialty => 'localTaste',
    RegionInsightType.culturalPractice || RegionInsightType.etiquette =>
      'etiquette',
    RegionInsightType.supply ||
    RegionInsightType.openingStatus ||
    RegionInsightType.regulation => 'practical',
  };

  static int _verificationDebt(RegionBrief brief) => brief.insights.fold(
    0,
    (total, insight) =>
        total +
        switch (insight.verification) {
          InsightVerificationState.conflicting => 6,
          InsightVerificationState.candidate => 4,
          InsightVerificationState.singleSource when insight.timeSensitive => 3,
          InsightVerificationState.singleSource => 1,
          InsightVerificationState.authoritative ||
          InsightVerificationState.corroborated => 0,
        },
  );

  static int _completenessRank(RegionBriefCompleteness value) => switch (value) {
    RegionBriefCompleteness.identityOnly => 0,
    RegionBriefCompleteness.partial => 1,
    RegionBriefCompleteness.actionable => 2,
    RegionBriefCompleteness.comprehensive => 3,
  };

  static int _evidenceWeight(RegionBrief brief) {
    final verified = brief.insights.where((item) {
      return item.verification == InsightVerificationState.authoritative ||
          item.verification == InsightVerificationState.corroborated;
    }).length;
    final strongSources = brief.sources.where((item) {
      return item.qualityTier == InsightQualityTier.s ||
          item.qualityTier == InsightQualityTier.a;
    }).length;
    return brief.insights.length * 4 +
        verified * 3 +
        brief.sources.length * 2 +
        strongSources;
  }
}
''', encoding='utf-8')

# Controller: add a third, distinct request mode while retaining one state machine.
provider = 'lib/src/features/explore/application/region_brief_providers.dart'
replace_once(
    provider,
    "    this.manualExpansion = false,\n    this.lastExpandedAt,\n",
    "    this.manualExpansion = false,\n    this.verification = false,\n    this.lastExpandedAt,\n    this.lastVerifiedAt,\n",
)
replace_once(
    provider,
    "  final bool manualExpansion;\n  final DateTime? lastExpandedAt;\n",
    "  final bool manualExpansion;\n  final bool verification;\n  final DateTime? lastExpandedAt;\n  final DateTime? lastVerifiedAt;\n",
)
replace_once(
    provider,
    "  bool get isExpanding =>\n      manualExpansion &&\n      (status == RegionBriefLoadStatus.loading ||\n          status == RegionBriefLoadStatus.refreshing);\n",
    "  bool get isBusy =>\n      status == RegionBriefLoadStatus.loading ||\n      status == RegionBriefLoadStatus.refreshing;\n\n  bool get isExpanding => manualExpansion && isBusy;\n\n  bool get isVerifying => verification && isBusy;\n",
)
replace_once(provider, "  Future<void> load({bool manual = false}) async {", "  Future<void> load({bool manual = false, bool verification = false}) async {")
replace_once(
    provider,
    "    if (manual) _automaticRetries = 0;\n    final generation = ++_generation;\n    var previous = state.brief;\n    final previousExpandedAt = state.lastExpandedAt;\n",
    "    if (manual || verification) _automaticRetries = 0;\n    var previous = state.brief;\n    if (verification && !RegionBriefRequestPolicy.needsVerification(previous)) {\n      return;\n    }\n    final generation = ++_generation;\n    final previousExpandedAt = state.lastExpandedAt;\n    final previousVerifiedAt = state.lastVerifiedAt;\n",
)
replace_once(
    provider,
    "      manualExpansion: manual,\n      lastExpandedAt: previousExpandedAt,\n",
    "      manualExpansion: manual,\n      verification: verification,\n      lastExpandedAt: previousExpandedAt,\n      lastVerifiedAt: previousVerifiedAt,\n",
)
# The same loading-state anchor appears once more after cache recovery.
replace_once(
    provider,
    "            manualExpansion: manual,\n            lastExpandedAt: previousExpandedAt,\n",
    "            manualExpansion: manual,\n            verification: verification,\n            lastExpandedAt: previousExpandedAt,\n            lastVerifiedAt: previousVerifiedAt,\n",
)
replace_once(
    provider,
    "            lastExpandedAt: previousExpandedAt,\n          );\n",
    "            lastExpandedAt: previousExpandedAt,\n            lastVerifiedAt: previousVerifiedAt,\n          );\n",
)
replace_once(
    provider,
    "      final plan = RegionBriefRequestPolicy.plan(profile, manual: manual);\n",
    "      final plan = verification\n          ? RegionBriefRequestPolicy.verificationPlan(profile, previous!)\n          : RegionBriefRequestPolicy.plan(profile, manual: manual);\n",
)
replace_once(
    provider,
    "        manual: manual,\n      );\n",
    "        manual: manual,\n        verification: verification,\n      );\n",
)
replace_once(
    provider,
    "        lastExpandedAt: manual && incoming.hasUsableFacts\n            ? DateTime.now().toUtc()\n            : previousExpandedAt,\n      );\n      _scheduleRetryIfNeeded(incoming, manual: manual);\n",
    "        lastExpandedAt: manual && !keepPrevious && incoming.hasUsableFacts\n            ? DateTime.now().toUtc()\n            : previousExpandedAt,\n        lastVerifiedAt:\n            verification && !keepPrevious && incoming.hasUsableFacts\n            ? DateTime.now().toUtc()\n            : previousVerifiedAt,\n      );\n      _scheduleRetryIfNeeded(\n        incoming,\n        manual: manual,\n        verification: verification,\n      );\n",
)
# Preserve verification timestamp in both error paths.
text = Path(provider).read_text(encoding='utf-8')
text = text.replace(
    "        lastExpandedAt: previousExpandedAt,\n      );\n    } on Object {",
    "        lastExpandedAt: previousExpandedAt,\n        lastVerifiedAt: previousVerifiedAt,\n      );\n    } on Object {",
    1,
)
text = text.replace(
    "        lastExpandedAt: previousExpandedAt,\n      );\n    }\n  }\n\n  void _scheduleRetryIfNeeded",
    "        lastExpandedAt: previousExpandedAt,\n        lastVerifiedAt: previousVerifiedAt,\n      );\n    }\n  }\n\n  void _scheduleRetryIfNeeded",
    1,
)
Path(provider).write_text(text, encoding='utf-8')
replace_once(
    provider,
    "  void _scheduleRetryIfNeeded(RegionBrief brief, {required bool manual}) {",
    "  void _scheduleRetryIfNeeded(\n    RegionBrief brief, {\n    required bool manual,\n    required bool verification,\n  }) {",
)
replace_once(
    provider,
    "      unawaited(load(manual: manual));\n",
    "      unawaited(load(manual: manual, verification: verification));\n",
)

# UI: expose verification only when the policy identifies evidence debt.
ui = 'lib/src/presentation_v2/explore/v2_region_brief_expansion.dart'
replace_once(
    ui,
    "import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';\n",
    "import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';\nimport 'package:luma_nest/src/features/explore/application/region_brief_request_policy.dart';\n",
)
replace_once(
    ui,
    "    required this.onExpand,\n  });\n",
    "    required this.onExpand,\n    required this.onVerify,\n  });\n",
)
replace_once(ui, "  final VoidCallback onExpand;\n", "  final VoidCallback onExpand;\n  final VoidCallback onVerify;\n")
replace_once(
    ui,
    "    final lastExpandedAt = state.lastExpandedAt;\n",
    "    final lastExpandedAt = state.lastExpandedAt;\n    final lastVerifiedAt = state.lastVerifiedAt;\n    final verificationTargets =\n        RegionBriefRequestPolicy.verificationTargetCount(brief);\n    final showVerification = verificationTargets > 0;\n",
)
replace_once(
    ui,
    "                      state.isExpanding ? '正在扩展探索' : '扩展探索',\n",
    "                      state.isVerifying\n                          ? '正在核验重点信息'\n                          : state.isExpanding\n                          ? '正在扩展探索'\n                          : '扩展探索',\n",
)
replace_once(
    ui,
    "                      _scenePromise(brief.profile),\n",
    "                      state.isVerifying\n                          ? '仅核对候选、冲突和时效性单一来源，不重写已经成立的事实。'\n                          : _scenePromise(brief.profile),\n",
)
replace_once(ui, "          if (state.isExpanding) ...[", "          if (state.isExpanding || state.isVerifying) ...[")
replace_once(
    ui,
    "              brief.refresh.refreshingMissions.isEmpty\n                  ? '正在检索审核来源并核对区域事实。'\n",
    "              brief.refresh.refreshingMissions.isEmpty\n                  ? state.isVerifying\n                        ? '正在检索官方或独立来源，核对弱证据。'\n                        : '正在检索审核来源并核对区域事实。'\n",
)
replace_once(
    ui,
    "              if (lastExpandedAt != null)\n                _BriefMetricChip(label: '上次扩展 ${_time(lastExpandedAt)}'),\n",
    "              if (verificationTargets > 0)\n                _BriefMetricChip(label: '$verificationTargets 条待核验'),\n              if (lastExpandedAt != null)\n                _BriefMetricChip(label: '上次扩展 ${_time(lastExpandedAt)}'),\n              if (lastVerifiedAt != null)\n                _BriefMetricChip(label: '上次核验 ${_time(lastVerifiedAt)}'),\n",
)
replace_once(ui, "          if (state.errorCode != null && !state.isExpanding) ...[", "          if (state.errorCode != null && !state.isBusy) ...[")
replace_once(ui, "              onPressed: state.isExpanding ? null : onExpand,", "              onPressed: state.isBusy ? null : onExpand,")
replace_once(
    ui,
    "                state.isExpanding\n                    ? CupertinoIcons.arrow_2_circlepath\n",
    "                state.isBusy\n                    ? CupertinoIcons.arrow_2_circlepath\n",
)
replace_once(ui, "              label: Text(state.isExpanding ? '正在核对资料' : '主动扩展区域资料'),", "              label: Text(state.isBusy ? '正在核对资料' : '主动扩展区域资料'),")
replace_once(
    ui,
    "          if (brief.sources.isNotEmpty) ...[\n",
    "          if (showVerification) ...[\n            const SizedBox(height: 8),\n            SizedBox(\n              width: double.infinity,\n              child: FilledButton.tonalIcon(\n                key: const Key('v2-verify-region-brief'),\n                onPressed: state.isBusy ? null : onVerify,\n                icon: const Icon(CupertinoIcons.check_mark_seal, size: 17),\n                label: Text(\n                  state.isVerifying ? '正在核验区域信息' : '核验候选与冲突信息',\n                ),\n                style: FilledButton.styleFrom(\n                  foregroundColor: V2Palette.moss,\n                  backgroundColor: V2Palette.mossSoft,\n                  padding: const EdgeInsets.symmetric(vertical: 13),\n                  shape: RoundedRectangleBorder(\n                    borderRadius: BorderRadius.circular(16),\n                  ),\n                  textStyle: const TextStyle(fontWeight: FontWeight.w900),\n                ),\n              ),\n            ),\n          ],\n          if (brief.sources.isNotEmpty) ...[\n",
)
replace_once(
    ui,
    "            '只在你主动触发时扩大检索范围；候选、单一来源与冲突信息会明确标记，不会伪装成已确认事实。',\n",
    "            '扩展会扩大资料范围；核验只针对弱证据。只有新增来源或证据等级真实改善时才替换现有简报。',\n",
)

# Page integration: same controller, distinct user action.
page = 'lib/src/presentation_v2/explore/v2_explore_page.dart'
replace_once(
    page,
    "        onRefresh: () =>\n            ref.read(regionBriefControllerProvider.notifier).load(manual: true),\n",
    "        onRefresh: () =>\n            ref.read(regionBriefControllerProvider.notifier).load(manual: true),\n        onVerify: () => ref\n            .read(regionBriefControllerProvider.notifier)\n            .load(verification: true),\n",
)
replace_once(
    page,
    "    required this.onRefresh,\n    required this.onOpenMap,\n",
    "    required this.onRefresh,\n    required this.onVerify,\n    required this.onOpenMap,\n",
)
replace_once(page, "  final VoidCallback onRefresh;\n", "  final VoidCallback onRefresh;\n  final VoidCallback onVerify;\n")
replace_once(
    page,
    "                  state.isExpanding ? '正在扩展区域资料' : '正在更新区域资料',\n",
    "                  state.isVerifying\n                      ? '正在核验候选与冲突信息'\n                      : state.isExpanding\n                      ? '正在扩展区域资料'\n                      : '正在更新区域资料',\n",
)
replace_once(
    page,
    "                onExpand: onRefresh,\n              ),\n",
    "                onExpand: onRefresh,\n                onVerify: onVerify,\n              ),\n",
)

# Discovery contract and search intent.
models = 'services/lumanest-discovery-service/app/models.py'
replace_once(
    models,
    '    activation_type: Literal["user_manual", "foreground_opportunistic"] = Field(alias="activationType")',
    '    activation_type: Literal["user_manual", "foreground_opportunistic", "ai_verification"] = Field(alias="activationType")',
)
worker = 'services/lumanest-discovery-service/app/worker.py'
replace_once(
    worker,
    "        if not job.region.locale.startswith(\"zh\"):\n            return (\n                f\"{area} {job.region.mission_type} recent\",\n                f\"{area} {job.region.mission_type} official\",\n                f\"{area} {job.region.mission_type} local\",\n            )\n",
    "        if job.activation_type == 'ai_verification':\n            if not job.region.locale.startswith(\"zh\"):\n                return (\n                    f\"{area} {job.region.mission_type} official notice\",\n                    f\"{area} {job.region.mission_type} independent verification\",\n                    f\"{area} photography access restriction\",\n                )\n            return (\n                f\"{area} {job.region.mission_type} 官方 公告\",\n                f\"{area} {job.region.mission_type} 独立来源 核实\",\n                f\"{area} 摄影 开放 管制\",\n            )\n        if not job.region.locale.startswith(\"zh\"):\n            return (\n                f\"{area} {job.region.mission_type} recent\",\n                f\"{area} {job.region.mission_type} official\",\n                f\"{area} {job.region.mission_type} local\",\n            )\n",
)

# Policy tests.
policy_test = 'test/features/explore/region_brief_request_policy_test.dart'
text = Path(policy_test).read_text(encoding='utf-8')
anchor = "\n  test('a different region replaces the previous brief normally', () {"
if text.count(anchor) != 1:
    raise SystemExit('policy test anchor mismatch')
new_tests = r'''

  test('verification targets only weak evidence sections and stays bounded', () {
    final brief = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.event, verification: InsightVerificationState.candidate, timeSensitive: true),
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.conflicting, timeSensitive: true),
        _insight(type: RegionInsightType.localFood, verification: InsightVerificationState.singleSource),
        _insight(type: RegionInsightType.architecture, verification: InsightVerificationState.corroborated),
      ],
    );

    expect(RegionBriefRequestPolicy.needsVerification(brief), isTrue);
    expect(RegionBriefRequestPolicy.verificationTargetCount(brief), 2);
    expect(
      RegionBriefRequestPolicy.verificationSections(brief),
      const ['practical', 'happeningNow'],
    );
    final plan = RegionBriefRequestPolicy.verificationPlan(
      _profile(settlement: SettlementType.historicTown),
      brief,
    );
    expect(plan.activationType, 'ai_verification');
    expect(plan.radiusMeters, 15000);
    expect(plan.requestedSections, const ['practical', 'happeningNow']);
  });

  test('verification adopts a real evidence improvement', () {
    final previous = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.conflicting, timeSensitive: true),
      ],
      sourceCount: 2,
    );
    final incoming = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.corroborated, timeSensitive: true),
      ],
      sourceCount: 2,
    );

    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: previous,
        incoming: incoming,
        manual: false,
        verification: true,
      ),
      isFalse,
    );
  });

  test('verification cannot improve by deleting weak facts or sources', () {
    final previous = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.event, verification: InsightVerificationState.candidate, timeSensitive: true),
        _insight(type: RegionInsightType.regulation, verification: InsightVerificationState.conflicting, timeSensitive: true),
      ],
      sourceCount: 2,
    );
    final incoming = _brief(
      regionId: 'hangzhou',
      insights: [
        _insight(type: RegionInsightType.event, verification: InsightVerificationState.corroborated, timeSensitive: true),
      ],
      sourceCount: 1,
    );

    expect(
      RegionBriefRequestPolicy.shouldKeepPrevious(
        previous: previous,
        incoming: incoming,
        manual: false,
        verification: true,
      ),
      isTrue,
    );
  });
'''
text = text.replace(anchor, new_tests + anchor)
text = text.replace(
    "  bool usable = true,\n}) {",
    "  bool usable = true,\n  List<RegionInsight> insights = const [],\n  int sourceCount = 0,\n}) {",
)
text = text.replace("    insights: const [],\n    sources: const [],", "    insights: insights,\n    sources: List.generate(\n      sourceCount,\n      (index) => InsightEvidence(\n        id: 'source-$index',\n        sourcePolicyId: 'policy-$index',\n        publisher: 'Publisher $index',\n        title: 'Source $index',\n        url: Uri.parse('https://example.org/$index'),\n        observedAt: now,\n        qualityTier: index == 0 ? InsightQualityTier.a : InsightQualityTier.b,\n        license: 'reviewed',\n        version: '1',\n      ),\n    ),")
text += r'''

RegionInsight _insight({
  required RegionInsightType type,
  required InsightVerificationState verification,
  bool timeSensitive = false,
}) {
  final now = DateTime.utc(2026, 8, 5, 3);
  return RegionInsight(
    id: '${type.name}-${verification.name}',
    regionId: 'hangzhou',
    type: type,
    title: type.name,
    summary: '事实摘要',
    verification: verification,
    factIds: const ['fact'],
    evidenceIds: const ['source-0'],
    observedAt: now,
    expiresAt: now.add(const Duration(hours: 6)),
    timeSensitive: timeSensitive,
    actionability: InsightActionability.detail,
  );
}
'''
Path(policy_test).write_text(text, encoding='utf-8')

# Widget tests: wire the new callback and assert conditional visibility.
widget_test = 'test/presentation_v2/explore/v2_region_brief_expansion_test.dart'
text = Path(widget_test).read_text(encoding='utf-8')
text = text.replace("    var expanded = false;\n", "    var expanded = false;\n    var verified = false;\n", 1)
text = text.replace("                    onExpand: () => expanded = true,\n", "                    onExpand: () => expanded = true,\n                    onVerify: () => verified = true,\n", 1)
text = text.replace("    expect(expanded, isTrue);\n", "    expect(expanded, isTrue);\n\n    await tester.tap(find.byKey(const Key('v2-verify-region-brief')));\n    await tester.pump();\n    expect(verified, isTrue);\n", 1)
text = text.replace("            onExpand: () {},\n", "            onExpand: () {},\n            onVerify: () {},\n", 1)
anchor = "\n  testWidgets('expansion progress exposes active missions and disables action', ("
if text.count(anchor) != 1:
    raise SystemExit('widget test anchor mismatch')
hidden_test = r'''

  testWidgets('verification action stays hidden for strong evidence', (tester) async {
    final brief = _brief(strongOnly: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: V2RegionBriefExpansionCard(
            brief: brief,
            state: RegionBriefState(
              status: RegionBriefLoadStatus.ready,
              brief: brief,
            ),
            onExpand: () {},
            onVerify: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('v2-verify-region-brief')), findsNothing);
    expect(tester.takeException(), isNull);
  });
'''
text = text.replace(anchor, hidden_test + anchor)
text = text.replace("RegionBrief _brief({List<String> missions = const []}) {", "RegionBrief _brief({List<String> missions = const [], bool strongOnly = false}) {")
text = text.replace("  final insights = [\n", "  final insights = strongOnly\n      ? [\n          _insight(\n            now: now,\n            id: 'photo',\n            type: RegionInsightType.photographyTheme,\n            title: '街巷与传统建筑',\n            verification: InsightVerificationState.corroborated,\n            evidenceIds: const ['source-official', 'source-local'],\n          ),\n        ]\n      : [\n", 1)
Path(widget_test).write_text(text, encoding='utf-8')

# Discovery tests for the new bounded activation.
discovery_test = 'services/lumanest-discovery-service/tests/test_region_brief_request_modes.py'
text = Path(discovery_test).read_text(encoding='utf-8')
text += r'''


def test_ai_verification_activation_is_scoped_and_deduped():
    payload = _brief_payload(
        activation="ai_verification",
        sections=["happeningNow", "practical"],
    )
    request = RegionBriefRequest.model_validate(payload)
    missions = DiscoveryStore._brief_missions(request)

    assert request.activation_type == "ai_verification"
    assert missions == ["humanityEvents", "openingAndClosure"]
    assert request.dedupe_payload()["activationType"] == "ai_verification"
'''
Path(discovery_test).write_text(text, encoding='utf-8')

# Worker query regression lives with existing worker tests if present.
worker_test = Path('services/lumanest-discovery-service/tests/test_worker.py')
text = worker_test.read_text(encoding='utf-8')
text += r'''


def test_ai_verification_queries_prioritize_official_and_independent_sources():
    job = _job(activation_type="ai_verification")
    queries = BrokerClient._queries(job)

    assert len(queries) == 3
    assert any("官方" in query for query in queries)
    assert any("独立来源" in query for query in queries)
    assert any("管制" in query for query in queries)
'''
worker_test.write_text(text, encoding='utf-8')

# Documentation.
doc = Path('docs/expanded-exploration-v1.md')
text = doc.read_text(encoding='utf-8')
text += r'''

## 定向证据核验

区域简报只在存在以下证据债务时显示“核验候选与冲突信息”：候选事实、来源冲突，或时效性内容只有单一来源。核验请求使用 `ai_verification` 激活类型，最多覆盖四个实际有问题的内容分区，不重跑整份简报，也不扩大默认前台抓取。

核验继续受来源白名单、URL 安全策略、抓取授权、查询上限和缓存约束。客户端只有在新结果不减少完整度、事实数量与来源数量，并且真实降低证据债务或提升证据强度时才采用；删除弱事实、减少来源或单纯重写措辞不构成核验成功。高质量简报不显示常驻核验入口。
'''
doc.write_text(text, encoding='utf-8')
