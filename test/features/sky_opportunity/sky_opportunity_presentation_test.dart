import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/sky_opportunity/application/sky_opportunity_providers.dart';
import 'package:luma_nest/src/features/sky_opportunity/data/sky_opportunity_repository.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/features/sky_opportunity/presentation/sky_opportunity_detail_page.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 14, 37);

  testWidgets(
    'eligible result becomes the Today object without a second fixed slot',
    (tester) async {
      final forecast = _forecast(now: now);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentTimeProvider.overrideWithValue(() => now),
            skyOpportunityRepositoryProvider.overrideWithValue(
              _Repository(
                DailySkyOpportunities(
                  todaySunset: forecast,
                  flags: const SkyOpportunityFeatureFlags(
                    providerEnabled: true,
                    cardEnabled: true,
                  ),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: V2TodayPage(initialSnapshot: _snapshot(now)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('今晚可能有晚霞。'), findsOneWidget);
      expect(find.text('查看拍摄建议'), findsOneWidget);
      expect(find.textContaining('双模型判断：较一致'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('暂无晚霞预测'), findsNothing);
    },
  );

  testWidgets('unavailable result reserves no sky opportunity widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTimeProvider.overrideWithValue(() => now),
          skyOpportunityRepositoryProvider.overrideWithValue(
            _Repository(DailySkyOpportunities.unavailable()),
          ),
        ],
        child: MaterialApp(home: V2TodayPage(initialSnapshot: _snapshot(now))),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('今晚可能有晚霞。'), findsNothing);
    expect(find.text('现在没有明确窗口，适合慢一点观察。'), findsOneWidget);
  });

  testWidgets('night home never keeps a past sunset as its action anchor', (
    tester,
  ) async {
    final nightNow = DateTime.utc(2026, 7, 18, 15, 20);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentTimeProvider.overrideWithValue(() => nightNow),
          skyOpportunityRepositoryProvider.overrideWithValue(
            _Repository(DailySkyOpportunities.unavailable()),
          ),
        ],
        child: MaterialApp(
          home: V2TodayPage(
            initialSnapshot: ContextSnapshot(
              id: 'night-home',
              observedAt: nightNow,
              expiresAt: nightNow.add(const Duration(minutes: 20)),
              primaryScene: SceneType.village,
              dayPhase: DayPhase.night,
              weather: WeatherType.cloudy,
              activeRoute: false,
              cloudCoverPercent: 88,
              visibilityKilometers: 7,
              precipitationMillimeters: 0,
              windSpeedMetersPerSecond: 2,
              sunrise: DateTime.utc(
                nightNow.year,
                nightNow.month,
                nightNow.day,
                5,
                11,
              ),
              sunset: DateTime.utc(
                nightNow.year,
                nightNow.month,
                nightNow.day,
                14,
                59,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('可以开始准备明日日出。'), findsOneWidget);
    expect(find.text('查看驾车候选'), findsOneWidget);
    expect(find.text('18:59 日落'), findsNothing);
    expect(find.textContaining('街巷与人的关系'), findsNothing);
  });

  testWidgets(
    'a local shooting session remains ahead of a city-level sky signal',
    (tester) async {
      final snapshot = ContextFixtures.lakeSunset(observedAt: now);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentTimeProvider.overrideWithValue(() => now),
            skyOpportunityRepositoryProvider.overrideWithValue(
              _Repository(
                DailySkyOpportunities(todaySunset: _forecast(now: now)),
              ),
            ),
          ],
          child: MaterialApp(home: V2TodayPage(initialSnapshot: snapshot)),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('这个窗口值得你提前到场。'), findsOneWidget);
      expect(find.text('今晚可能有晚霞。'), findsNothing);
    },
  );

  testWidgets(
    'detail labels source, disclaimer, models and stale data honestly',
    (tester) async {
      final forecast = _forecast(now: now, stale: true);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: SkyOpportunityDetailPage(
              eventType: SkyOpportunityEventType.sunset,
              dayOffset: 0,
              initialForecast: forecast,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('今日晚霞拍摄建议'), findsOneWidget);
      expect(find.text('怎么观察'), findsOneWidget);
      expect(find.text('西侧开阔天空'), findsOneWidget);
      expect(find.text('条件较好'), findsOneWidget);
      expect(find.text('0.288'), findsNothing);
      expect(find.text('0.700'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pump();
      expect(find.text('GFS 与 EC'), findsOneWidget);
      expect(find.textContaining('晚霞预测数据来源：SunsetBot'), findsOneWidget);
      expect(find.textContaining('结果仅用于摄影创作参考'), findsOneWidget);
      expect(find.textContaining('数据更新稍有延迟'), findsOneWidget);
      expect(find.textContaining('发生概率'), findsNothing);
    },
  );
}

ContextSnapshot _snapshot(DateTime now) {
  return ContextSnapshot(
    id: 'sky-test',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 20)),
    primaryScene: SceneType.city,
    dayPhase: DayPhase.sunset,
    weather: WeatherType.clear,
    activeRoute: false,
    location: const GeoPoint(latitude: 30.2741, longitude: 120.1551),
    sunset: now.add(const Duration(hours: 1)),
  );
}

SkyOpportunityForecast _forecast({required DateTime now, bool stale = false}) {
  return SkyOpportunityForecast(
    id: 'skyopp_hangzhou_sunset',
    requestedCity: '杭州',
    resolvedCity: '杭州',
    eventType: SkyOpportunityEventType.sunset,
    dayOffset: 0,
    eventTime: now.add(const Duration(hours: 1)),
    providerLocalTimeZone: 'Asia/Shanghai',
    level: 'strong',
    label: '条件较好',
    confidence: SkyOpportunityConfidence.high,
    agreement: SkyOpportunityAgreement.strong,
    primaryReason: '双模型判断较一致',
    clarityLevel: 'good',
    clarityLabel: '大气较通透',
    models: [
      SkyOpportunityModelForecast(
        model: 'GFS',
        providerLabel: '中烧',
        eventTime: now.add(const Duration(hours: 1)),
        status: 'ok',
        parseStatus: 'ok',
      ),
      SkyOpportunityModelForecast(
        model: 'EC',
        providerLabel: '中烧',
        eventTime: now.add(const Duration(hours: 1)),
        status: 'ok',
        parseStatus: 'ok',
      ),
    ],
    fetchedAt: now.subtract(stale ? const Duration(hours: 3) : Duration.zero),
    expiresAt: now.add(const Duration(minutes: 90)),
    cacheStatus: stale ? 'stale' : 'hit',
    isStale: stale,
    providerStatus: stale ? 'degraded' : 'healthy',
    attribution: '晚霞预测数据来源：SunsetBot',
    presentation: SkyOpportunityPresentation(
      proactiveEligible: true,
      paperEligible: true,
      notificationEligible: false,
      ambientStrength: stale ? .095 : .19,
    ),
  );
}

class _Repository implements SkyOpportunityRepository {
  const _Repository(this.value);
  final DailySkyOpportunities value;
  @override
  Future<DailySkyOpportunities> fetchDaily({
    required double latitude,
    required double longitude,
    SkyOpportunityDailyFocus focus = SkyOpportunityDailyFocus.next,
  }) async => value;
}
