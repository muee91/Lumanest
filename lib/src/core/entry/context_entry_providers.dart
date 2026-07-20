import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/scenario/scenario_orchestrator.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';

/// Process-scoped canonical entry store shared by all surfaces.
///
/// Domain providers publish normalized [ContextEntry] batches here while
/// presentation providers query surface-specific projections. Keeping the
/// store above feature modules prevents Explore, Today and Route from
/// maintaining independent copies of the same contextual fact.
final contextEntryStoreProvider = Provider<ContextEntryStore>((ref) {
  return InMemoryContextEntryStore();
});

final contextEntryStoreRevisionProvider = StreamProvider<int>((ref) async* {
  final store = ref.watch(contextEntryStoreProvider);
  yield store.current.revision;
  await for (final delta in store.watch()) {
    yield delta.nextRevision;
  }
});

/// Canonical Explore projection. Consumers should select the slot they need
/// instead of ranking NearbyPlace objects again inside presentation widgets.
final exploreSurfaceCompositionProvider = Provider<SurfaceComposition>((ref) {
  final store = ref.watch(contextEntryStoreProvider);
  final streamedRevision = ref.watch(contextEntryStoreRevisionProvider);
  final revision = streamedRevision.asData?.value ?? store.current.revision;
  final now = ref.watch(currentTimeProvider)();
  return const ScenarioOrchestrator().composeExplore(
    entries: store.query(const EntryQuery(surface: EntrySurface.explore)),
    now: now,
    revision: revision,
  );
});
