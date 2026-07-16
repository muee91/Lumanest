import 'photography_opportunity.dart';

/// Separates factual, established opportunities from creative prompts.
/// Creative prompts deliberately contain no statement about current weather,
/// light, wildlife, safety, or a recommended place.
enum PhotographyInspirationKind { factualOpportunity, creativePrompt }

class PhotographyInspirationProposal {
  const PhotographyInspirationProposal._({
    required this.id,
    required this.kind,
    required this.label,
    required this.detail,
    this.opportunityId,
    this.evidence = const <PhotographyEvidence>[],
  });

  factory PhotographyInspirationProposal.factual(
    PhotographyOpportunity opportunity,
  ) => PhotographyInspirationProposal._(
    id: opportunity.id,
    kind: PhotographyInspirationKind.factualOpportunity,
    label: opportunity.title,
    detail: opportunity.evidence
        .where((evidence) => evidence.supports)
        .map((evidence) => evidence.statement)
        .join(' '),
    opportunityId: opportunity.id,
    evidence: List.unmodifiable(opportunity.evidence),
  );

  factory PhotographyInspirationProposal.creative({
    required String id,
    required String label,
    required String prompt,
  }) => PhotographyInspirationProposal._(
    id: id,
    kind: PhotographyInspirationKind.creativePrompt,
    label: label,
    detail: prompt,
  );

  final String id;
  final PhotographyInspirationKind kind;
  final String label;
  final String detail;
  final String? opportunityId;
  final List<PhotographyEvidence> evidence;

  bool get isFactual => kind == PhotographyInspirationKind.factualOpportunity;
}

abstract final class PhotographyInspirationProposalBuilder {
  static List<PhotographyInspirationProposal> build({
    Iterable<PhotographyOpportunity> opportunities =
        const <PhotographyOpportunity>[],
    Iterable<PhotographyInspirationProposal> creative =
        const <PhotographyInspirationProposal>[],
  }) {
    final result = <PhotographyInspirationProposal>[];
    final seen = <String>{};
    for (final opportunity in opportunities) {
      if (seen.add(opportunity.id)) {
        result.add(PhotographyInspirationProposal.factual(opportunity));
      }
    }
    for (final proposal in creative) {
      if (proposal.kind != PhotographyInspirationKind.creativePrompt) continue;
      if (seen.add(proposal.id)) result.add(proposal);
    }
    return List.unmodifiable(result);
  }
}
