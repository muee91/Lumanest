import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_adapter.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

/// The client mirrors the server's opening ceiling (docs/core-1.0-scope.md
/// §7.1) for the entries it composes locally, because a locally built entry
/// otherwise reaches a surface no rule engine ever authorised.
void main() {
  final observedAt = DateTime.utc(2026, 7, 18, 10);

  ContextEntry build({
    required Duration snapshotAge,
    ShootingConfidenceBand band = ShootingConfidenceBand.high,
  }) {
    // The fixture window always opens ten minutes after its own observation, so
    // ageing the snapshot is what moves the window across the two-hour horizon.
    final session = ContextFixtures.waterEveningSession(
      observedAt: observedAt,
      confidenceBand: band,
    );
    return ContextEntryAdapter.fromShootingSession(
      session,
      observedAt: observedAt.subtract(snapshotAge),
    );
  }

  test('窗口在证据视野内且条件成立时才可占用通知表面', () {
    final entry = build(snapshotAge: Duration.zero);

    expect(
      entry.validFrom.difference(entry.observedAt),
      const Duration(minutes: 10),
      reason: 'fixture 的窗口在观测后十分钟开始，处于两小时视野内',
    );
    expect(entry.allowedSurfaces, contains(EntrySurface.notification));
    expect(entry.allowedSurfaces, contains(EntrySurface.widget));
  });

  test('超出两小时视野的窗口不占用任何不被注视的表面', () {
    final entry = build(snapshotAge: const Duration(hours: 3));

    expect(entry.allowedSurfaces, isNot(contains(EntrySurface.notification)));
    expect(entry.allowedSurfaces, contains(EntrySurface.widget));
    expect(entry.allowedSurfaces, contains(EntrySurface.today));
  });

  test('limited 置信档既不打扰也不常驻，因为它说不满自己暗示的内容', () {
    final entry = build(
      snapshotAge: Duration.zero,
      band: ShootingConfidenceBand.limited,
    );

    expect(entry.allowedSurfaces, isNot(contains(EntrySurface.notification)));
    expect(entry.allowedSurfaces, isNot(contains(EntrySurface.widget)));
    expect(entry.allowedSurfaces, entryBaseSurfaces);
  });

  test('路线页面属于基础表面，任何置信档都不该被它排除', () {
    // `app/v5.py` grants the route surface to every entry while the local
    // adapter omitted it, so a locally composed window never reached the route
    // timeline even though the server considered it qualified.
    for (final band in ShootingConfidenceBand.values) {
      expect(
        build(snapshotAge: Duration.zero, band: band).allowedSurfaces,
        containsAll(entryBaseSurfaces),
        reason: '$band 档也必须占用四个基础表面',
      );
    }
  });

  test('天空机会只把服务端的资格判定映射成表面，绝不自己拓宽', () {
    ContextEntry fromSky({required bool notificationEligible}) {
      return ContextEntryAdapter.fromSkyOpportunity(
        SkyOpportunityForecast(
          id: 'skyopp',
          requestedCity: '海宁',
          resolvedCity: '海宁',
          eventType: SkyOpportunityEventType.sunset,
          dayOffset: 0,
          eventTime: observedAt.add(const Duration(minutes: 40)),
          providerLocalTimeZone: 'Asia/Shanghai',
          level: 'very_strong',
          label: '高质量机会',
          confidence: SkyOpportunityConfidence.high,
          agreement: SkyOpportunityAgreement.strong,
          primaryReason: '双模型判断较一致',
          clarityLevel: 'very_good',
          clarityLabel: '天空通透',
          models: const [],
          fetchedAt: observedAt,
          expiresAt: observedAt.add(const Duration(minutes: 90)),
          cacheStatus: 'hit',
          isStale: false,
          providerStatus: 'healthy',
          attribution: '晚霞预测数据来源：SunsetBot',
          presentation: SkyOpportunityPresentation(
            proactiveEligible: true,
            paperEligible: true,
            notificationEligible: notificationEligible,
            ambientStrength: 0.2,
          ),
        ),
        observedAt: observedAt,
      );
    }

    expect(
      fromSky(notificationEligible: true).allowedSurfaces,
      containsAll(<EntrySurface>{
        EntrySurface.widget,
        EntrySurface.notification,
      }),
    );
    // An ineligible verdict used to be parsed and then ignored, so the broker's
    // two-hour decision never reached the delivery layer at all.
    expect(
      fromSky(notificationEligible: false).allowedSurfaces,
      isNot(contains(EntrySurface.notification)),
    );
    expect(
      fromSky(notificationEligible: false).allowedSurfaces,
      isNot(contains(EntrySurface.widget)),
    );
  });

  test('安全条目拥有任意提前量的打扰资格，与普通机会不同', () {
    final entry = ContextEntryAdapter.fromManifestItem(
      const ManifestItem(
        id: 'warning-1',
        title: '大风橙色预警',
        action: ManifestAction.openSafetyDetail,
      ),
      summary: '未来六小时阵风可达九级',
      observedAt: observedAt,
      expiresAt: observedAt.add(const Duration(hours: 6)),
    );

    expect(entry.allowedSurfaces, entrySafetySurfaces);
    expect(entry.kind, EntryKind.safety);
  });
}
