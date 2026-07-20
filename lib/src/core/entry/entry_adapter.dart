import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_action.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/entry/entry_provenance.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/next_photography_window.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

abstract final class ContextEntryAdapter {
  static ContextEntry fromShootingSession(
    ShootingSession session, {
    required DateTime observedAt,
  }) {
    final phase = session.primaryPhaseValue;
    final target = session.targetCandidates.firstOrNull;
    final confidence = switch (session.confidenceBand) {
      ShootingConfidenceBand.high => .9,
      ShootingConfidenceBand.medium => .7,
      ShootingConfidenceBand.limited => .4,
    };
    return _entry(
      id: _stableId(
        'photography',
        '${session.id}:${_dateKey(session.startsAt)}',
      ),
      kind: EntryKind.photographyOpportunity,
      sourceId: session.id,
      revision: _revision(observedAt),
      observedAt: observedAt,
      validFrom: session.startsAt,
      expiresAt: session.expiresAt,
      evidenceConfidence: confidence,
      basePriority: EntryPriority.p1,
      severity: EntrySeverity.info,
      payload: OpportunityEntryPayload(
        definitionId: session.id,
        instanceId: session.id,
        sessionId: session.id,
        targetId: target?.id,
        peaksAt: phase.startsAt,
        conditionBand: session.conditionBand,
      ),
      presentation: EntryPresentation(
        variant: EntryPresentationVariant.shootingSession,
        eyebrow: _sessionEyebrow(session.kind),
        title: _sessionTitle(session),
        detail: [
          if (target != null) target.name else '暂无验证机位',
          ...session.factors
              .take(2)
              .map((item) => '${item.label} ${item.value}'),
        ].join(' · '),
        judgement: switch (session.trend) {
          ShootingTrend.improving => '风与云正在把窗口慢慢打开。',
          ShootingTrend.stable => '光线条件稳定，可以围绕主阶段安排。',
          ShootingTrend.weakening => '机会正在收窄，先看时间再决定。',
        },
        timeLabel:
            '${_time(phase.startsAt)}—${_time(phase.endsAt)} · ${_conditionLabel(session.conditionBand)}',
        actionLabel: target == null ? '看时间轴' : '进入机会',
        accent: _sessionAccent(session.conditionBand),
      ),
      actions: [
        EntryAction(
          type: EntryActionType.openShootingWindow,
          targetId: session.id,
        ),
      ],
      provenance: [
        EntryProvenance(sourceId: session.id, observedAt: observedAt),
      ],
      dedupeKey: '${session.kind.name}:${_dateKey(session.startsAt)}',
      suppressionKeys: {session.kind.name},
      allowedSurfaces: const {
        EntrySurface.today,
        EntrySurface.explore,
        EntrySurface.shootingWindow,
        EntrySurface.widget,
      },
    );
  }

  static ContextEntry fromSkyOpportunity(
    SkyOpportunityForecast forecast, {
    required DateTime observedAt,
  }) {
    final eventTime = forecast.eventTime;
    return _entry(
      id: _stableId('sky', forecast.id),
      kind: EntryKind.photographyOpportunity,
      sourceId: forecast.id,
      revision: _revision(forecast.fetchedAt),
      observedAt: forecast.fetchedAt,
      validFrom: eventTime ?? observedAt,
      expiresAt: forecast.expiresAt,
      evidenceConfidence: switch (forecast.confidence) {
        SkyOpportunityConfidence.high => .9,
        SkyOpportunityConfidence.medium => .7,
        SkyOpportunityConfidence.low => .4,
        SkyOpportunityConfidence.unavailable => 0,
      },
      basePriority: EntryPriority.p2,
      severity: EntrySeverity.info,
      payload: OpportunityEntryPayload(
        definitionId: 'event.sky.${forecast.eventType.name}',
        instanceId: forecast.id,
        peaksAt: eventTime,
      ),
      presentation: EntryPresentation(
        variant: EntryPresentationVariant.skyOpportunity,
        eyebrow: forecast.dayOffset == 0
            ? '今日${forecast.eventLabel}'
            : '明日${forecast.eventLabel}',
        title: _skyTitle(forecast),
        detail: '双模型判断：${forecast.agreementLabel} · ${forecast.clarityLabel}',
        judgement: '${forecast.eventLabel}有机会，${forecast.primaryReason}。',
        timeLabel: eventTime == null
            ? '暂无可信时间'
            : '${_time(eventTime)} 前后${forecast.isStale ? ' · 数据更新稍有延迟' : ''}',
        actionLabel: '查看拍摄建议',
        accent: forecast.confidence == SkyOpportunityConfidence.low
            ? EntryAccent.mutedInk
            : EntryAccent.ember,
      ),
      actions: [
        EntryAction(
          type: EntryActionType.openAstronomyDetail,
          targetId: '${forecast.eventType.name}:${forecast.dayOffset}',
        ),
      ],
      provenance: [
        EntryProvenance(
          sourceId: forecast.attribution,
          observedAt: forecast.fetchedAt,
        ),
      ],
      dedupeKey: '${forecast.eventType.name}:${forecast.dayOffset}',
      suppressionKeys: const {},
      allowedSurfaces: const {
        EntrySurface.today,
        EntrySurface.explore,
        EntrySurface.shootingWindow,
      },
    );
  }

  static ContextEntry fromNextWindow(
    NextPhotographyWindowDecision decision, {
    required DateTime observedAt,
  }) => _entry(
    id: _stableId('system-opportunity', decision.stableId),
    kind: EntryKind.system,
    sourceId: decision.stableId,
    revision: _revision(observedAt),
    observedAt: observedAt,
    validFrom: observedAt,
    expiresAt: observedAt.add(const Duration(hours: 2)),
    evidenceConfidence: .5,
    basePriority: EntryPriority.p2,
    severity: EntrySeverity.info,
    payload: SystemEntryPayload(stateCode: decision.kind.name),
    presentation: EntryPresentation(
      variant: EntryPresentationVariant.nextWindow,
      eyebrow: decision.eyebrow,
      title: decision.title,
      detail: decision.detail,
      judgement: decision.judgement,
      timeLabel: decision.timeLabel,
      actionLabel: decision.actionLabel,
      accent: decision.kind == NextPhotographyWindowKind.nightSky
          ? EntryAccent.night
          : EntryAccent.ember,
    ),
    actions: [
      EntryAction(
        type: EntryActionType.openExplore,
        query: decision.action == NextPhotographyWindowAction.exploreNightSky
            ? 'night-sky'
            : 'sunrise',
      ),
    ],
    provenance: [
      EntryProvenance(
        sourceId: 'local-window-resolver',
        observedAt: observedAt,
      ),
    ],
    dedupeKey: decision.stableId,
    allowedSurfaces: const {EntrySurface.today, EntrySurface.explore},
  );

  static ContextEntry fromManifestItem(
    ManifestItem item, {
    required String summary,
    required DateTime observedAt,
    required DateTime expiresAt,
  }) {
    final safety =
        item.safetyLevel != null ||
        item.action == ManifestAction.openSafetyDetail;
    final action = _actionFromManifest(item);
    return _entry(
      id: _stableId(safety ? 'safety' : 'manifest', item.id),
      kind: safety ? EntryKind.safety : EntryKind.photographyOpportunity,
      sourceId: item.id,
      revision: _revision(item.observedAt ?? observedAt),
      observedAt: item.observedAt ?? observedAt,
      validFrom: item.observedAt ?? observedAt,
      expiresAt: item.expiresAt ?? expiresAt,
      evidenceConfidence: item.confidence ?? (safety ? 1 : .5),
      basePriority: safety ? EntryPriority.p0 : EntryPriority.p2,
      severity: safety ? EntrySeverity.warning : EntrySeverity.info,
      payload: safety
          ? SafetyEntryPayload(
              eventId: item.id,
              action: _contextAction(item.action),
              authorityRequired: item.authorityUri != null,
            )
          : OpportunityEntryPayload(definitionId: item.id, instanceId: item.id),
      presentation: EntryPresentation(
        variant: safety
            ? EntryPresentationVariant.safety
            : EntryPresentationVariant.manifestOpportunity,
        eyebrow: safety ? '安全提醒' : '当前机会',
        title: item.title,
        detail: safety ? '查看依据与行动建议' : summary,
        judgement: summary,
        timeLabel: safety ? '现在' : '环境更新后持续观察',
        actionLabel: safety ? '查看安全建议' : '查看',
        accent: safety ? EntryAccent.danger : EntryAccent.sky,
      ),
      actions: [EntryAction(type: action, targetId: item.id)],
      provenance: [
        EntryProvenance(
          sourceId: item.source?.name ?? 'manifest',
          observedAt: item.observedAt ?? observedAt,
          sourceUri: item.authorityUri,
        ),
      ],
      dedupeKey: item.id,
      allowedSurfaces: safety
          ? const {
              EntrySurface.today,
              EntrySurface.route,
              EntrySurface.notification,
            }
          : const {EntrySurface.today, EntrySurface.inspiration},
    );
  }

  static ContextEntry fromNearbyPlace(
    NearbyPlace place, {
    required DateTime observedAt,
  }) {
    final reviewed = place.reviewedTarget;
    return _entry(
      id: _stableId('place', place.id),
      kind: EntryKind.place,
      sourceId: place.id,
      revision: _revision(place.cachedAt ?? observedAt),
      observedAt: place.cachedAt ?? observedAt,
      validFrom: place.cachedAt ?? observedAt,
      expiresAt: observedAt.add(
        place.isOfflineCache
            ? const Duration(hours: 6)
            : const Duration(minutes: 15),
      ),
      evidenceConfidence: reviewed ? .85 : .45,
      basePriority: EntryPriority.p2,
      severity: EntrySeverity.info,
      payload: PlaceEntryPayload(
        placeId: place.id,
        category: place.category.name,
        distanceMeters: place.distanceMeters,
        travelDurationSeconds: place.drivingDurationSeconds,
        reviewedTarget: reviewed,
      ),
      presentation: EntryPresentation(
        variant: EntryPresentationVariant.manifestOpportunity,
        eyebrow: place.category.label,
        title: place.name,
        detail: [
          if (place.administrativeLabel != null) place.administrativeLabel!,
          if (!reviewed) '探索线索，尚未审核为机位',
        ].join(' · '),
        timeLabel: place.drivingDurationSeconds == null
            ? '距此 ${place.distanceMeters}m'
            : '驾车约 ${((place.drivingDurationSeconds! + 59) ~/ 60)} 分钟',
        actionLabel: '查看地点',
        accent: EntryAccent.sky,
      ),
      actions: [
        EntryAction(type: EntryActionType.openPlaceDetail, targetId: place.id),
      ],
      provenance: [
        EntryProvenance(sourceId: 'nearby:${place.id}', observedAt: observedAt),
      ],
      dedupeKey: 'place:${place.id}',
      allowedSurfaces: const {
        EntrySurface.explore,
        EntrySurface.today,
        EntrySurface.route,
      },
    );
  }

  static ContextEntry quiet({
    required ContextSnapshot snapshot,
    required DateTime now,
    required DateTime? nextSunrise,
    required String detail,
  }) => _entry(
    id: _stableId('system', 'quiet:${snapshot.id}'),
    kind: EntryKind.system,
    sourceId: snapshot.id,
    revision: _revision(snapshot.observedAt),
    observedAt: snapshot.observedAt,
    validFrom: now,
    expiresAt: snapshot.expiresAt,
    evidenceConfidence: 1,
    basePriority: EntryPriority.p3,
    severity: EntrySeverity.info,
    payload: const SystemEntryPayload(stateCode: 'quiet'),
    presentation: EntryPresentation(
      variant: EntryPresentationVariant.quiet,
      eyebrow: '安静观察',
      title: snapshot.isStale ? '判断已经过期，先不要据此行动。' : '现在没有明确窗口，适合慢一点观察。',
      detail: snapshot.isStale ? '刷新数据后再做出发判断' : detail,
      judgement: detail,
      timeLabel: _solarLabel(snapshot, now, nextSunrise),
      actionLabel: '探索附近',
      accent: EntryAccent.sky,
    ),
    actions: const [EntryAction(type: EntryActionType.openExplore)],
    provenance: [
      EntryProvenance(
        sourceId: 'local-snapshot',
        observedAt: snapshot.observedAt,
      ),
    ],
    dedupeKey: 'quiet:${snapshot.id}',
    allowedSurfaces: const {EntrySurface.today},
  );

  static ContextEntry _entry({
    required String id,
    required EntryKind kind,
    required String sourceId,
    required int revision,
    required DateTime observedAt,
    required DateTime validFrom,
    required DateTime expiresAt,
    required double evidenceConfidence,
    required EntryPriority basePriority,
    required EntrySeverity severity,
    required EntryPayload payload,
    required EntryPresentation presentation,
    required Iterable<EntryAction> actions,
    required Iterable<EntryProvenance> provenance,
    required String dedupeKey,
    required Set<EntrySurface> allowedSurfaces,
    Set<String> suppressionKeys = const {},
  }) {
    final fingerprint = sha256
        .convert(
          utf8.encode(
            [
              id,
              revision,
              presentation.variant.name,
              presentation.eyebrow,
              presentation.title,
              presentation.detail,
              presentation.judgement,
              presentation.timeLabel,
              presentation.actionLabel,
            ].join('|'),
          ),
        )
        .toString();
    return ContextEntry(
      id: id,
      kind: kind,
      sourceNamespace: 'lumanest.local-entry-adapter',
      sourceId: sourceId,
      revision: revision,
      observedAt: observedAt,
      validFrom: validFrom,
      expiresAt: expiresAt,
      freshness: expiresAt.isAfter(DateTime.now().toUtc())
          ? EntryFreshness.fresh
          : EntryFreshness.expired,
      evidenceConfidence: evidenceConfidence.clamp(0, 1).toDouble(),
      basePriority: basePriority,
      severity: severity,
      geoScope: const EntryGeoScope(type: ContextGeoScope.region),
      allowedSurfaces: allowedSurfaces,
      actions: actions,
      presentation: presentation,
      payload: payload,
      provenance: provenance,
      dedupeKey: dedupeKey,
      suppressionKeys: suppressionKeys,
      contentFingerprint: 'sha256:$fingerprint',
    );
  }

  static int _revision(DateTime value) => value.toUtc().microsecondsSinceEpoch;

  static String _stableId(String kind, String source) =>
      'entry_${kind}_${sha256.convert(utf8.encode(source)).toString().substring(0, 24)}';

  static EntryActionType _actionFromManifest(ManifestItem item) =>
      switch (item.action) {
        ManifestAction.openShootingWindow => EntryActionType.openShootingWindow,
        ManifestAction.openExplore => EntryActionType.openExplore,
        ManifestAction.openRoute => EntryActionType.openRoute,
        ManifestAction.openPlaceDetail => EntryActionType.openPlaceDetail,
        ManifestAction.openAstronomyDetail =>
          EntryActionType.openAstronomyDetail,
        ManifestAction.openWildlifeDetail => EntryActionType.openWildlifeDetail,
        ManifestAction.openSafetyDetail => EntryActionType.openSafetyDetail,
        ManifestAction.openCreativeDetail => EntryActionType.openCreativeDetail,
        ManifestAction.dismiss => EntryActionType.dismiss,
      };

  static ContextAction _contextAction(ManifestAction action) =>
      switch (action) {
        ManifestAction.openShootingWindow => ContextAction.openShootingWindow,
        ManifestAction.openExplore => ContextAction.openExplore,
        ManifestAction.openRoute => ContextAction.openRoute,
        ManifestAction.openPlaceDetail => ContextAction.openPlaceDetail,
        ManifestAction.openAstronomyDetail => ContextAction.openAstronomyDetail,
        ManifestAction.openWildlifeDetail => ContextAction.openWildlifeDetail,
        ManifestAction.openSafetyDetail => ContextAction.openSafetyDetail,
        ManifestAction.openCreativeDetail => ContextAction.openCreativeDetail,
        ManifestAction.dismiss => ContextAction.dismiss,
      };

  static String _sessionEyebrow(ShootingSessionKind kind) => switch (kind) {
    ShootingSessionKind.generalMorning => '晨间光线',
    ShootingSessionKind.generalEvening => '晚间光线',
    ShootingSessionKind.waterMorning => '水岸晨光',
    ShootingSessionKind.waterEvening => '水岸晚光',
    ShootingSessionKind.mountainMorning => '山地晨光',
    ShootingSessionKind.mountainEvening => '山地晚光',
    ShootingSessionKind.cityBlueHour => '城市蓝调',
    ShootingSessionKind.cityAfterRain => '城市雨后',
    ShootingSessionKind.desertSideLight => '荒漠侧光',
    ShootingSessionKind.routeLightWindow => '沿途光窗',
  };

  static String _sessionTitle(ShootingSession session) =>
      switch ((session.conditionBand, session.confidenceBand)) {
        (_, ShootingConfidenceBand.limited) => '这次只适合观察，不建议出发。',
        (ShootingConditionBand.good, _) => '这个窗口值得你提前到场。',
        (ShootingConditionBand.fair, _) => '可以等待，但别急着出发。',
        (ShootingConditionBand.limited, _) => '条件有限，把它当作光线参考。',
      };

  static EntryAccent _sessionAccent(ShootingConditionBand value) =>
      switch (value) {
        ShootingConditionBand.good => EntryAccent.moss,
        ShootingConditionBand.fair => EntryAccent.ember,
        ShootingConditionBand.limited => EntryAccent.mutedInk,
      };

  static String _conditionLabel(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => '条件较好',
    ShootingConditionBand.fair => '条件一般',
    ShootingConditionBand.limited => '条件有限',
  };

  static String _skyTitle(SkyOpportunityForecast value) {
    if (value.dayOffset == 0 &&
        value.eventType == SkyOpportunityEventType.sunset) {
      return '今晚可能有晚霞。';
    }
    if (value.dayOffset == 0) return '今日朝霞值得留意。';
    return value.eventType == SkyOpportunityEventType.sunrise
        ? '明日朝霞值得留意。'
        : '明日晚霞值得留意。';
  }

  static String _solarLabel(
    ContextSnapshot snapshot,
    DateTime now,
    DateTime? nextSunrise,
  ) {
    final sunset = snapshot.sunset;
    if (sunset != null && sunset.isAfter(now)) return '${_time(sunset)} 日落';
    final sunrise = snapshot.sunrise;
    if (sunrise != null && sunrise.isAfter(now)) return '${_time(sunrise)} 日出';
    if (nextSunrise != null && nextSunrise.isAfter(now)) {
      return '${_time(nextSunrise)} 下次日出';
    }
    return '暂无可信出发时间';
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _dateKey(DateTime value) =>
      '${value.toUtc().year}-${value.toUtc().month}-${value.toUtc().day}';
}
