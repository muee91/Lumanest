import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/local_creative_affinity.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';

void main() {
  test('uses only canonical opportunity IDs and decays older recorded outcomes', () {
    final now = DateTime.utc(2026, 7, 17, 12);
    PhotographyOpportunityResult result(String id, PhotographyOpportunityOutcome outcome, DateTime at) =>
        PhotographyOpportunityResult.record(
          opportunityId: id,
          snapshotId: 'ctx',
          outcome: outcome,
          recordedAt: at,
        );
    final affinity = LocalCreativeAffinity.fromResults([
      result('photo-blueHour-2026071712', PhotographyOpportunityOutcome.shot, now),
      result('unknown-event', PhotographyOpportunityOutcome.shot, now),
      result('photo-reflection-2026010101', PhotographyOpportunityOutcome.missed, DateTime.utc(2026, 1, 1)),
    ], now: now);
    expect(affinity['blueHour'], greaterThan(0));
    expect(affinity['reflection'], lessThan(0));
    expect(affinity.containsKey('unknown'), isFalse);
  });
}
