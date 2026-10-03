import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';
import 'package:luma_nest/src/core/photography/active_shooting_intent.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/presentation_v2/opportunity/v2_opportunity_page.dart';

void main() {
  testWidgets('Field Mode stops location polling in background', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final target = _target();
    final snapshot = _snapshot(now, target);
    final location = _CountingLocationRepository(
      LocationReading(
        point: target.coordinate,
        recordedAt: now,
        accuracyMeters: 8,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        locationRepositoryProvider.overrideWithValue(location),
        environmentSnapshotProvider.overrideWith(
          () => _FixedEnvironmentController(snapshot),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: V2OpportunityPage(
            sessionId: snapshot.shootingSessions.single.id,
            initialSnapshot: snapshot,
            activeShootingIntent: ActiveShootingIntent(
              sessionId: snapshot.shootingSessions.single.id,
              targetId: target.id,
              createdAt: now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(location.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 45));
    expect(location.calls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(location.calls, 2);
  });
}

class _CountingLocationRepository implements LocationRepository {
  _CountingLocationRepository(this.reading);

  final LocationReading reading;
  int calls = 0;

  @override
  Future<LocationReading> current() async {
    calls += 1;
    return reading;
  }
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  _FixedEnvironmentController(this.snapshot);

  final ContextSnapshot snapshot;

  @override
  Future<ContextSnapshot> build() async => snapshot;
}

ContextSnapshot _snapshot(DateTime now, ShootingTarget target) {
  final base = ContextFixtures.lakeSunset(observedAt: now);
  final source = base.shootingSessions.single;
  final session = ShootingSession(
    id: source.id,
    kind: source.kind,
    title: source.title,
    startsAt: source.startsAt,
    endsAt: source.endsAt,
    primaryPhase: source.primaryPhase,
    conditionBand: source.conditionBand,
    confidenceBand: source.confidenceBand,
    trend: source.trend,
    phases: source.phases,
    factors: source.factors,
    trendSamples: source.trendSamples,
    targetCandidates: [target],
    recommendedCapabilities: source.recommendedCapabilities,
    ruleVersion: source.ruleVersion,
    expiresAt: source.expiresAt,
  );
  return ContextSnapshot(
    id: base.id,
    observedAt: base.observedAt,
    expiresAt: base.expiresAt,
    primaryScene: base.primaryScene,
    dayPhase: base.dayPhase,
    weather: base.weather,
    activeRoute: base.activeRoute,
    opportunityIds: base.opportunityIds,
    events: base.events,
    allowedActions: base.allowedActions,
    shootingSessions: [session],
    location: target.coordinate,
    windSpeedMetersPerSecond: base.windSpeedMetersPerSecond,
    visibilityKilometers: base.visibilityKilometers,
    precipitationMillimeters: base.precipitationMillimeters,
    cloudCoverPercent: base.cloudCoverPercent,
  );
}

ShootingTarget _target() => ShootingTarget(
  id: 'target_0123456789abcdef01234567',
  name: '审核湖岸机位',
  coordinate: const GeoPoint(latitude: 30.25, longitude: 120.15),
  supportedSessions: const [ShootingSessionKind.waterEvening],
  viewBearingDegrees: 282,
  bearingToleranceDegrees: 20,
  accessModes: const [ShootingTravelMode.driving],
  leadTimeMinutes: 10,
  arrivalRadiusMeters: 100,
  shorelineSide: ShootingShorelineSide.east,
  reviewedAt: DateTime.utc(2026, 9, 1),
  reviewReference: Uri.parse('https://review.example/target'),
  sourceAttribution: '审核目录',
  sourceLicense: 'CC-BY-4.0',
  sourceUrl: Uri.parse('https://source.example/target'),
);
