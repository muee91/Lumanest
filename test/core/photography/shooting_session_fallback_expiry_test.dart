import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

void main() {
  test('expired primary evidence can trigger a Plan B search', () {
    final observedAt = DateTime.utc(2026, 7, 17, 10);
    final session = ContextFixtures.waterEveningSession(observedAt: observedAt);

    expect(
      ShootingSessionFallback.shouldOfferPlanB(
        session,
        now: observedAt.add(const Duration(minutes: 16)),
      ),
      isTrue,
    );
  });
}
