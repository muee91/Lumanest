import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/server_manifest.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';

abstract final class ManifestPolicy {
  static UiManifest build(
    ContextSnapshot snapshot, {
    DateTime? now,
    CreativePersonalization? personalization,
  }) {
    final evaluatedAt = (now ?? DateTime.now()).toUtc();
    final effectivePersonalization =
        personalization ?? CreativePersonalization.neutral;
    final currentEvents = {
      for (final event in snapshot.events)
        if (!event.isExpiredAt(evaluatedAt)) event.id: event,
    };

    final serverManifest = snapshot.serverManifest;
    if (serverManifest != null) {
      return _buildFromServer(
        snapshot,
        serverManifest,
        currentEvents,
        effectivePersonalization,
      );
    }
    return _buildLocal(snapshot, currentEvents, effectivePersonalization);
  }

  // ---------------------------------------------------------------------------
  // Server manifest path
  // ---------------------------------------------------------------------------

  static UiManifest _buildFromServer(
    ContextSnapshot snapshot,
    ServerManifest serverManifest,
    Map<String, ContextEvent> currentEvents,
    CreativePersonalization personalization,
  ) {
    final layoutMode = LayoutMode.fromServerLayout(serverManifest.layout);

    // Creative: strictly primaryEventId + secondaryEventIds order.
    // Server-manifest creative entries must have a current unexpired event.
    final creativeIds = <String>[
      if (serverManifest.primaryEventId != null) serverManifest.primaryEventId!,
      ...serverManifest.secondaryEventIds,
    ];
    final creative = <ManifestItem>[];
    for (final id in creativeIds) {
      final event = currentEvents[id];
      if (event == null) continue;
      final template = _creativeItem(id);
      if (template != null) creative.add(template.withEvent(event));
    }
    final orderedCreative = _personalizeCreative(creative, personalization);
    final primary = orderedCreative.firstOrNull;
    final secondary = orderedCreative.skip(1).take(2).toList(growable: false);

    // Safety: union of serverManifest.safetyEventIds and all current unexpired
    // structured safety/wildlifeSafety events. Server omissions must not hide
    // safety events.
    final safety = _buildServerSafety(serverManifest, currentEvents);

    return UiManifest(
      layoutMode: layoutMode,
      summary: _summaryFor(snapshot, primary),
      primary: primary,
      secondary: secondary,
      safety: safety,
      inspirationPreview: _inspirationFor(primary),
    );
  }

  static List<ManifestItem> _buildServerSafety(
    ServerManifest serverManifest,
    Map<String, ContextEvent> currentEvents,
  ) {
    // Collect all current unexpired structured safety-channel events.
    final structuredSafetyIds = <String>[];
    for (final event in currentEvents.values) {
      if (event.channel == ContextEventChannel.safety ||
          event.channel == ContextEventChannel.wildlifeSafety) {
        structuredSafetyIds.add(event.id);
      }
    }

    // Ordered union: server-listed IDs first (if they have a current event),
    // then any current structured safety events the server missed.
    final seen = <String>{};
    final orderedIds = <String>[];
    for (final id in serverManifest.safetyEventIds) {
      if (currentEvents.containsKey(id) && seen.add(id)) {
        orderedIds.add(id);
      }
    }
    for (final id in structuredSafetyIds) {
      if (seen.add(id)) {
        orderedIds.add(id);
      }
    }

    return orderedIds
        .map((id) {
          final event = currentEvents[id]!;
          final template = _safetyItem(id) ?? _wildlifeSafetyItem(id);
          return template?.withEvent(event) ??
              _unknownSafetyItem(event).withEvent(event);
        })
        .whereType<ManifestItem>()
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Local fallback path (no server manifest)
  // ---------------------------------------------------------------------------

  static UiManifest _buildLocal(
    ContextSnapshot snapshot,
    Map<String, ContextEvent> currentEvents,
    CreativePersonalization personalization,
  ) {
    final structuredEventIds = snapshot.events.map((event) => event.id).toSet();

    final creative =
        [
              ...snapshot.opportunityIds.map(_creativeItem),
              ...snapshot.wildlifeEventIds.map(_wildlifeCreativeItem),
            ]
            .whereType<ManifestItem>()
            .where(
              (item) =>
                  !structuredEventIds.contains(item.id) ||
                  currentEvents.containsKey(item.id),
            )
            .map((item) => item.withEvent(currentEvents[item.id]))
            .toList(growable: false);

    // Safety always requires a structured unexpired event — bare IDs (including
    // bear-risk) without a matching structured event do not produce safety
    // entries.
    final safety =
        [
              ...snapshot.safetyEventIds.map(_safetyItem),
              ...snapshot.wildlifeEventIds.map(_wildlifeSafetyItem),
            ]
            .whereType<ManifestItem>()
            .where((item) => currentEvents.containsKey(item.id))
            .map((item) => item.withEvent(currentEvents[item.id]))
            .toList(growable: false);

    final orderedCreative = _personalizeCreative(creative, personalization);
    final primary = orderedCreative.firstOrNull;

    return UiManifest(
      layoutMode: snapshot.activeRoute
          ? LayoutMode.operation
          : primary == null
          ? LayoutMode.quiet
          : LayoutMode.opportunity,
      summary: _summaryFor(snapshot, primary),
      primary: primary,
      secondary: orderedCreative.skip(1).take(2).toList(growable: false),
      safety: safety,
      inspirationPreview: _inspirationFor(primary),
    );
  }

  static List<ManifestItem> _personalizeCreative(
    List<ManifestItem> creative,
    CreativePersonalization personalization,
  ) {
    if (creative.length < 2 ||
        !personalization.hasRecommendationPreferences ||
        personalization.recommendationIntensity <= 0.3) {
      return List.of(creative, growable: false);
    }

    final ranked = [
      for (var index = 0; index < creative.length; index += 1)
        _RankedCreative(
          item: creative[index],
          originalIndex: index,
          matched:
              personalization.matchesCreativeEvent(creative[index].id) ||
              personalization.affinityForCreativeEvent(creative[index].id) > 0,
        ),
    ];

    if (personalization.recommendationIntensity >= 0.8) {
      ranked.sort((first, second) {
        if (first.matched != second.matched) return first.matched ? -1 : 1;
        return first.originalIndex.compareTo(second.originalIndex);
      });
    } else {
      ranked.sort((first, second) {
        final firstRank = first.originalIndex - (first.matched ? 1 : 0);
        final secondRank = second.originalIndex - (second.matched ? 1 : 0);
        final rankComparison = firstRank.compareTo(secondRank);
        if (rankComparison != 0) return rankComparison;
        if (first.matched != second.matched) return first.matched ? -1 : 1;
        return first.originalIndex.compareTo(second.originalIndex);
      });
    }
    return ranked.map((entry) => entry.item).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Template factories
  // ---------------------------------------------------------------------------

  static ManifestItem? _creativeItem(String id) {
    if (id == 'regional-wildlife') {
      return const ManifestItem(
        id: 'regional-wildlife',
        title: '附近生态线索',
        action: ManifestAction.openWildlifeDetail,
      );
    }
    final definition = OpportunityCatalog.current.byId[id];
    if (definition == null || !definition.isActiveCore) return null;
    final degraded = definition.coreCapability == CoreCapabilityState.degraded;
    return ManifestItem(
      id: id,
      title: degraded
          ? definition.presentation.degradedName ?? definition.presentation.name
          : definition.presentation.name,
      action: ManifestAction.fromContextAction(definition.primaryAction),
    );
  }

  static ManifestItem? _safetyItem(String id) {
    return switch (id) {
      'thunderstorm' => const ManifestItem(
        id: 'thunderstorm',
        title: '雷暴正在接近',
        action: ManifestAction.openSafetyDetail,
      ),
      'strong-wind' => const ManifestItem(
        id: 'strong-wind',
        title: '当前风力较强',
        action: ManifestAction.openSafetyDetail,
      ),
      'heavy-rain' => const ManifestItem(
        id: 'heavy-rain',
        title: '当前降水较强',
        action: ManifestAction.openSafetyDetail,
      ),
      'unhealthy-air' => const ManifestItem(
        id: 'unhealthy-air',
        title: '当前空气质量不适合长时间户外拍摄',
        action: ManifestAction.openSafetyDetail,
      ),
      'hiking-return-check' => const ManifestItem(
        id: 'hiking-return-check',
        title: '留意返程时间',
        action: ManifestAction.openSafetyDetail,
      ),
      _ => null,
    };
  }

  static ManifestItem? _wildlifeCreativeItem(String id) {
    return switch (id) {
      'regional-wildlife' => const ManifestItem(
        id: 'regional-wildlife',
        title: '附近有野外线索',
        action: ManifestAction.openWildlifeDetail,
      ),
      _ => null,
    };
  }

  static ManifestItem? _wildlifeSafetyItem(String id) {
    return switch (id) {
      'bear-risk' => const ManifestItem(
        id: 'bear-risk',
        title: '进入熊类历史活动区域',
        action: ManifestAction.openSafetyDetail,
      ),
      'boar-risk' => const ManifestItem(
        id: 'boar-risk',
        title: '进入野猪历史活动区域',
        action: ManifestAction.openSafetyDetail,
      ),
      'snake-risk' => const ManifestItem(
        id: 'snake-risk',
        title: '进入蛇类历史活动区域',
        action: ManifestAction.openSafetyDetail,
      ),
      _ => null,
    };
  }

  /// Generic title for an unknown-but-structured safety event.
  static ManifestItem _unknownSafetyItem(ContextEvent event) {
    final title = event.source == ContextEventSource.official
        ? '官方安全预警'
        : '环境安全提醒';
    return ManifestItem(
      id: event.id,
      title: title,
      action: event.allowedAction != null
          ? ManifestAction.fromContextAction(event.allowedAction!)
          : ManifestAction.openSafetyDetail,
    );
  }

  static String _summaryFor(ContextSnapshot snapshot, ManifestItem? primary) {
    final definition = primary == null
        ? null
        : OpportunityCatalog.current.byId[primary.id];
    final opportunitySummary = primary?.id == 'regional-wildlife'
        ? '附近有公开的野生动物活动记录，适合放慢脚步观察。'
        : definition?.isActiveCore == true
        ? definition?.presentation.fallbackSummary
        : null;
    if (opportunitySummary != null) return opportunitySummary;
    if (primary?.action == ManifestAction.openAstronomyDetail) {
      return '已审核天象目录显示：${primary!.title}。实际可见性仍取决于本地天气与视野。';
    }

    if (snapshot.dayPhase == DayPhase.night) {
      return '夜已经深了，先看夜空条件或下一次晨光。';
    }

    return switch (snapshot.primaryScene) {
      SceneType.unknown => '环境数据已更新，暂时没有明确拍摄窗口。',
      SceneType.city => '光线平静，适合观察线条与人流。',
      SceneType.lake => '湖面暂时没有明显拍摄窗口。',
      SceneType.mountain => '山体光线条件暂不突出。',
      SceneType.desert => '留意地表纹理与远处层次。',
      SceneType.village => '慢下来观察街巷与人的关系。',
    };
  }

  static String _inspirationFor(ManifestItem? primary) {
    if (primary == null) return '';
    if (primary.id == 'regional-wildlife') return '野外线索🦌';
    final definition = OpportunityCatalog.current.byId[primary.id];
    if (definition?.isActiveCore == true) {
      return '${definition!.presentation.shortLabel}${definition.presentation.emoji}';
    }
    return primary.action == ManifestAction.openAstronomyDetail ? '看天象✨' : '';
  }
}

class _RankedCreative {
  const _RankedCreative({
    required this.item,
    required this.originalIndex,
    required this.matched,
  });

  final ManifestItem item;
  final int originalIndex;
  final bool matched;
}
