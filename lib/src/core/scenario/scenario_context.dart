import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/photography/next_photography_window.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

class ScenarioContext {
  const ScenarioContext({
    required this.surface,
    required this.now,
    required this.snapshot,
    required this.manifest,
    required this.narrative,
    required this.skyOpportunity,
    required this.nextWindow,
    required this.nextSunrise,
  });

  final EntrySurface surface;
  final DateTime now;
  final ContextSnapshot snapshot;
  final UiManifest manifest;
  final ManifestNarrative? narrative;
  final SkyOpportunityForecast? skyOpportunity;
  final NextPhotographyWindowDecision? nextWindow;
  final DateTime? nextSunrise;
}
