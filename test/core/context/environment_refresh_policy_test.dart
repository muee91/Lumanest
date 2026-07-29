import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/environment_refresh_policy.dart';

void main() {
  test('refreshes at the next local midnight before a later expiry', () {
    final now = DateTime(2026, 7, 29, 23, 55);
    final snapshot = ContextFixtures.quietCity(observedAt: now.toUtc());

    expect(
      EnvironmentRefreshPolicy.nextRefreshAt(snapshot: snapshot, now: now),
      DateTime.utc(2026, 7, 29, 16),
    );
  });

  test('retries expired snapshots with a bounded delay', () {
    final now = DateTime.utc(2026, 7, 30, 1, 35);
    final snapshot = ContextFixtures.quietCity(
      observedAt: now.subtract(const Duration(hours: 1)),
    );

    expect(
      EnvironmentRefreshPolicy.nextRefreshAt(snapshot: snapshot, now: now),
      now.add(const Duration(minutes: 1)),
    );
  });

  test('resuming across a local day boundary refreshes a live snapshot', () {
    final snapshot = ContextFixtures.quietCity(
      observedAt: DateTime.utc(2026, 7, 29, 15, 55),
    );

    expect(
      EnvironmentRefreshPolicy.needsRefreshOnResume(
        snapshot: snapshot,
        now: DateTime(2026, 7, 30, 0, 1),
      ),
      isTrue,
    );
  });

  test(
    'short foreground switches preserve a still-valid same-day snapshot',
    () {
      final now = DateTime(2026, 7, 30, 9);
      final snapshot = ContextFixtures.quietCity(observedAt: now.toUtc());

      expect(
        EnvironmentRefreshPolicy.needsRefreshOnResume(
          snapshot: snapshot,
          now: now.add(const Duration(minutes: 2)),
        ),
        isFalse,
      );
    },
  );
}
