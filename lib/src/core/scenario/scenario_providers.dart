import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/core/photography/next_photography_window.dart';
import 'package:luma_nest/src/core/scenario/scenario_context.dart';
import 'package:luma_nest/src/core/scenario/scenario_orchestrator.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';
import 'package:luma_nest/src/features/sky_opportunity/application/sky_opportunity_providers.dart';

final scenarioOrchestratorProvider = Provider<ScenarioOrchestrator>((ref) {
  return const ScenarioOrchestrator();
});

final todaySurfaceCompositionProvider =
    Provider.family<SurfaceComposition, ContextSnapshot>((ref, snapshot) {
      final now = ref.watch(currentTimeProvider)();
      final point = snapshot.location;
      final daily = point == null
          ? null
          : ref
                .watch(
                  dailySkyOpportunitiesProvider((
                    latitude: point.latitude,
                    longitude: point.longitude,
                    focus: skyOpportunityFocusForSnapshot(snapshot, now),
                  )),
                )
                .asData
                ?.value;
      final narrative = ref
          .watch(manifestNarrativeProvider(snapshot))
          .asData
          ?.value;
      final nextSunrise = _nextSunrise(ref, snapshot, now);
      final nextWindow = NextPhotographyWindowResolver.resolve(
        snapshot: snapshot,
        now: now,
        nextSunrise: nextSunrise,
      );
      return ref
          .watch(scenarioOrchestratorProvider)
          .composeToday(
            ScenarioContext(
              surface: EntrySurface.today,
              now: now,
              snapshot: snapshot,
              manifest: ref.watch(personalizedManifestProvider(snapshot)),
              narrative: narrative,
              skyOpportunity: daily?.activeHomeOpportunity(now),
              nextWindow: nextWindow,
              nextSunrise: nextSunrise,
            ),
          );
    });

DateTime? _nextSunrise(Ref ref, ContextSnapshot snapshot, DateTime now) {
  final current = snapshot.sunrise;
  if (current != null && current.isAfter(now)) return current;
  final point = snapshot.location;
  if (point == null) return current?.add(const Duration(days: 1));
  return ref
      .read(solarServiceProvider)
      .calculate(
        point: point,
        moment: now.add(const Duration(hours: 12)),
        utcOffset: now.timeZoneOffset,
      )
      .sunrise;
}
