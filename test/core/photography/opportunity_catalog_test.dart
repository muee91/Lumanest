import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/generated/opportunity_catalog.g.dart';

void main() {
  test('generated catalog preserves all engineering-spec counts', () {
    final opportunities = _objects(generatedOpportunityCatalogJson);
    final timing = _objects(generatedTimingPoliciesJson);
    final tags = _objects(generatedCanonicalTagsJson);
    final creative = _objects(generatedCreativePromptsJson);

    expect(opportunityCatalogVersion, 1);
    expect(opportunities, hasLength(48));
    expect(
      opportunities.where((item) => item['catalogTier'] == 'core'),
      hasLength(16),
    );
    expect(
      opportunities.where((item) => item['catalogTier'] == 'legacyOnly'),
      hasLength(3),
    );
    expect(
      opportunities.where((item) => item['catalogTier'] == 'reserved'),
      hasLength(29),
    );
    expect(
      opportunities.where((item) => item['coreCapability'] == 'available'),
      hasLength(6),
    );
    expect(
      opportunities.where((item) => item['coreCapability'] == 'degraded'),
      hasLength(7),
    );
    expect(
      opportunities.where((item) => item['coreCapability'] == 'unavailable'),
      hasLength(3),
    );
    expect(timing, hasLength(16));
    expect(tags, hasLength(96));
    expect(creative, hasLength(48));
  });

  test('catalog references only generated timing policies and tags', () {
    final opportunities = _objects(generatedOpportunityCatalogJson);
    final timingIds = _objects(
      generatedTimingPoliciesJson,
    ).map((item) => item['id']).toSet();
    final tagIds = _objects(
      generatedCanonicalTagsJson,
    ).map((item) => item['id']).toSet();
    final creative = _objects(generatedCreativePromptsJson);

    for (final opportunity in opportunities.where(
      (item) => item['catalogTier'] == 'core',
    )) {
      expect(timingIds, contains(opportunity['timingPolicy']));
    }
    for (final prompt in creative) {
      expect(tagIds, containsAll((prompt['techniqueTags'] as List<Object?>)));
      expect(
        tagIds,
        containsAll((prompt['equipmentRequirement'] as List<Object?>)),
      );
    }
  });
}

List<Map<String, Object?>> _objects(String source) {
  return (jsonDecode(source) as List<Object?>)
      .cast<Map<String, Object?>>()
      .toList(growable: false);
}
