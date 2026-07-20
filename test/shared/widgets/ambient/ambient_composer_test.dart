import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/features/sky_opportunity/presentation/sky_opportunity_ambient.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_composer.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const visualMapper = AmbientVisualMapper();
  const opportunityMapper = SkyOpportunityAmbientMapper();
  const composer = AmbientComposer();
  late AmbientPresetBundle bundle;

  setUpAll(() async {
    bundle = await AmbientPresetBundle.load(rootBundle);
  });

  test('composer preserves semantic colors and maps motion and wind', () {
    final snapshot = _snapshot();
    final visual = visualMapper.resolveSnapshot(snapshot, Brightness.light);
    final preset = bundle.select(
      weather: snapshot.weather,
      dayPhase: snapshot.dayPhase,
    );
    final composition = composer.compose(
      visualState: visual,
      preset: preset,
      quality: AmbientQualityTier.balanced,
    );

    expect(composition.semanticState, visual);
    expect(composition.field.colors.first, visual.palette.topColor);
    expect(composition.field.colors.last, visual.palette.bottomColor);
    expect(composition.field.timeSpeed, visual.motionIntensity);
    expect(composition.field.blendAngleDegrees, -75);
    AmbientPresetValidator.validateField(
      composition.field,
      path: 'composition',
    );
  });

  test('static quality has no time or warp motion', () {
    final snapshot = _snapshot();
    final visual = visualMapper.resolveSnapshot(snapshot, Brightness.light);
    final composition = composer.compose(
      visualState: visual,
      preset: bundle.require('energy_saver_static'),
      quality: AmbientQualityTier.static,
    );

    expect(composition.field.timeSpeed, 0);
    expect(composition.field.warpStrength, 0);
    expect(composition.field.animateGrain, isFalse);
  });

  test('safety remains authoritative over opportunity color enhancement', () {
    final safeSnapshot = _snapshot();
    final safetySnapshot = _snapshot(safety: true);
    final safeBase = visualMapper.resolveSnapshot(
      safeSnapshot,
      Brightness.light,
    );
    final safetyBase = visualMapper.resolveSnapshot(
      safetySnapshot,
      Brightness.light,
    );
    final forecast = _forecast();
    final enhanced = opportunityMapper.apply(
      base: safeBase,
      snapshot: safeSnapshot,
      forecast: forecast,
    );
    final suppressed = opportunityMapper.apply(
      base: safetyBase,
      snapshot: safetySnapshot,
      forecast: forecast,
    );

    expect(enhanced.palette, isNot(safeBase.palette));
    expect(suppressed, safetyBase);

    final preset = bundle.require('clear_sunset');
    final enhancedComposition = composer.compose(
      visualState: enhanced,
      preset: preset,
      quality: AmbientQualityTier.balanced,
    );
    final safetyComposition = composer.compose(
      visualState: suppressed,
      preset: preset,
      quality: AmbientQualityTier.balanced,
    );
    expect(
      enhancedComposition.field.colors.first,
      isNot(safetyComposition.field.colors.first),
    );
    expect(safetyComposition.field.colors.first, safetyBase.palette.topColor);
  });
}

ContextSnapshot _snapshot({bool safety = false}) {
  final now = DateTime.utc(2026, 7, 19, 10);
  return ContextSnapshot(
    id: safety ? 'ambient-safety' : 'ambient-safe',
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 20)),
    primaryScene: SceneType.lake,
    dayPhase: DayPhase.sunset,
    weather: WeatherType.clear,
    activeRoute: false,
    windSpeedMetersPerSecond: 4,
    windDirectionDegrees: 285,
    cloudCoverPercent: 20,
    safetyEventIds: safety ? const ['thunderstorm'] : const [],
  );
}

SkyOpportunityForecast _forecast() {
  final now = DateTime.utc(2026, 7, 19, 10);
  return SkyOpportunityForecast(
    id: 'ambient-opportunity',
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
    presentation: const SkyOpportunityPresentation(
      proactiveEligible: true,
      paperEligible: true,
      notificationEligible: false,
      ambientStrength: .25,
    ),
  );
}
