import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/features/sky_opportunity/presentation/sky_opportunity_ambient.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

void main() {
  const mapper = SkyOpportunityAmbientMapper();
  final base = const AmbientVisualMapper().resolveSnapshot(
    _snapshot(),
    Brightness.light,
  );

  test(
    'creative warmth is bounded to 25 percent and preserves weather motion',
    () {
      final result = mapper.apply(
        base: base,
        snapshot: _snapshot(),
        forecast: _forecast(.25),
      );
      expect(
        result.palette.topColor,
        Color.lerp(base.palette.topColor, const Color(0xFFFF5D86), .25),
      );
      expect(result.motionIntensity, base.motionIntensity);
      expect(result.cloudOpacity, base.cloudOpacity);
      expect(result.precipitation, base.precipitation);
    },
  );

  test(
    'safety state completely suppresses the creative color contribution',
    () {
      final result = mapper.apply(
        base: base,
        snapshot: _snapshot(safety: true),
        forecast: _forecast(.25),
      );
      expect(identical(result, base), isTrue);
    },
  );

  test(
    'missing enhancement leaves the authoritative weather field untouched',
    () {
      expect(
        identical(
          mapper.apply(base: base, snapshot: _snapshot(), forecast: null),
          base,
        ),
        isTrue,
      );
    },
  );
}

ContextSnapshot _snapshot({bool safety = false}) {
  final now = DateTime.utc(2026, 7, 18, 10);
  return ContextSnapshot(
    id: 'ambient-sky',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 20)),
    primaryScene: SceneType.city,
    dayPhase: DayPhase.sunset,
    weather: WeatherType.cloudy,
    activeRoute: false,
    safetyEventIds: safety ? const ['thunderstorm'] : const [],
    cloudCoverPercent: 70,
    windSpeedMetersPerSecond: 3,
  );
}

SkyOpportunityForecast _forecast(double ambientStrength) {
  final now = DateTime.utc(2026, 7, 18, 10);
  return SkyOpportunityForecast(
    id: 'skyopp',
    requestedCity: '杭州',
    resolvedCity: '杭州',
    eventType: SkyOpportunityEventType.sunset,
    dayOffset: 0,
    eventTime: now.add(const Duration(hours: 1)),
    providerLocalTimeZone: 'Asia/Shanghai',
    level: 'very_strong',
    label: '高质量机会',
    confidence: SkyOpportunityConfidence.high,
    agreement: SkyOpportunityAgreement.strong,
    primaryReason: '双模型判断较一致',
    clarityLevel: 'very_good',
    clarityLabel: '天空通透',
    models: const [],
    fetchedAt: now,
    expiresAt: now.add(const Duration(minutes: 90)),
    cacheStatus: 'hit',
    isStale: false,
    providerStatus: 'healthy',
    attribution: '晚霞预测数据来源：SunsetBot',
    presentation: SkyOpportunityPresentation(
      proactiveEligible: true,
      paperEligible: true,
      notificationEligible: false,
      ambientStrength: ambientStrength,
    ),
  );
}
