import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/context/scene_evidence_repository.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

void main() {
  test(
    'scene evidence repository contract returns explicit evidence',
    () async {
      const repository = _FakeSceneEvidenceRepository();
      final evidence = await repository.fetch(
        const GeoPoint(latitude: 30.25, longitude: 120.15),
      );
      expect(evidence.waterBody, isTrue);
      expect(evidence.source, SceneEvidenceSource.amapSemanticEntities);
    },
  );
}

class _FakeSceneEvidenceRepository implements SceneEvidenceRepository {
  const _FakeSceneEvidenceRepository();

  @override
  Future<SceneEvidence> fetch(GeoPoint location) async => const SceneEvidence(
    waterBody: true,
    source: SceneEvidenceSource.amapSemanticEntities,
  );
}
