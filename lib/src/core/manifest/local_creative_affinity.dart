import 'package:luma_nest/src/features/library/domain/user_library.dart';

/// Bounded local-only outcome signal. Unknown historic IDs remain neutral.
abstract final class LocalCreativeAffinity {
  static Map<String, double> fromResults(
    Iterable<PhotographyOpportunityResult> results, {
    DateTime? now,
  }) {
    final moment = (now ?? DateTime.now()).toUtc();
    final scores = <String, double>{};
    for (final result in results) {
      final kind = _kind(result.opportunityId);
      if (kind == null) continue;
      final age = moment
          .difference(result.recordedAt.toUtc())
          .inDays
          .clamp(0, 365);
      final decay = 1 / (1 + age / 45);
      final signal = switch (result.outcome) {
        PhotographyOpportunityOutcome.shot => 1.0,
        PhotographyOpportunityOutcome.missed => -0.35,
        PhotographyOpportunityOutcome.skipped => -0.15,
      };
      scores[kind] = (scores[kind] ?? 0) + signal * decay;
    }
    return {
      for (final entry in scores.entries)
        if (entry.value != 0)
          entry.key: (entry.value / 3).clamp(-1, 1).toDouble(),
    };
  }

  static String? _kind(String id) {
    final match = RegExp(r'^photo-([A-Za-z]+)-').firstMatch(id);
    return match?.group(1);
  }
}
