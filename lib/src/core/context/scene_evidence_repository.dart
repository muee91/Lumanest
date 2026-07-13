import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract interface class SceneEvidenceRepository {
  Future<SceneEvidence> fetch(GeoPoint location);
}

enum SceneEvidenceFailureKind { configuration, network, response }

class SceneEvidenceFailure implements Exception {
  const SceneEvidenceFailure(this.kind);
  final SceneEvidenceFailureKind kind;

  @override
  String toString() => 'SceneEvidenceFailure($kind)';
}
