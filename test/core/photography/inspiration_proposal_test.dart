import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/inspiration_proposal.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';

void main() {
  PhotographyOpportunity factualOpportunity() => PhotographyOpportunity(
    id: 'blue-hour',
    title: '蓝调窗口',
    startsAt: DateTime.utc(2026, 7, 17, 11),
    peaksAt: DateTime.utc(2026, 7, 17, 11, 10),
    expiresAt: DateTime.utc(2026, 7, 17, 11, 30),
    confidence: .8,
    evidence: const [
      PhotographyEvidence(
        id: 'solar',
        kind: PhotographyEvidenceKind.light,
        statement: '蓝调时段已由日月计算确认。',
        confidence: .9,
      ),
    ],
  );

  test(
    'factual proposals retain established evidence and opportunity link',
    () {
      final proposal = PhotographyInspirationProposal.factual(
        factualOpportunity(),
      );

      expect(proposal.isFactual, isTrue);
      expect(proposal.opportunityId, 'blue-hour');
      expect(proposal.detail, contains('日月计算'));
      expect(proposal.evidence, hasLength(1));
    },
  );

  test(
    'creative proposals cannot carry environmental evidence or opportunity',
    () {
      final proposal = PhotographyInspirationProposal.creative(
        id: 'frame-shadow',
        label: '找一处边框',
        prompt: '用前景遮住画面一角，再决定主体的位置。',
      );

      expect(proposal.isFactual, isFalse);
      expect(proposal.opportunityId, isNull);
      expect(proposal.evidence, isEmpty);
      expect(proposal.detail, isNot(contains('正在')));
    },
  );

  test(
    'builder keeps factual and creative proposals distinct and deduplicated',
    () {
      final creative = PhotographyInspirationProposal.creative(
        id: 'frame-shadow',
        label: '找一处边框',
        prompt: '用前景遮住画面一角。',
      );
      final output = PhotographyInspirationProposalBuilder.build(
        opportunities: [factualOpportunity(), factualOpportunity()],
        creative: [creative, creative],
      );

      expect(output.map((proposal) => proposal.id), [
        'blue-hour',
        'frame-shadow',
      ]);
      expect(output.map((proposal) => proposal.kind), [
        PhotographyInspirationKind.factualOpportunity,
        PhotographyInspirationKind.creativePrompt,
      ]);
    },
  );
}
