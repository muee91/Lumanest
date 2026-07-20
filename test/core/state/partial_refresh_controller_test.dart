import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/entry/entry_adapter.dart';
import 'package:luma_nest/src/core/state/environment_state.dart';
import 'package:luma_nest/src/core/state/partial_refresh_controller.dart';
import 'package:luma_nest/src/core/state/state_slice.dart';

void main() {
  test('weather slice update preserves the current entry set atomically', () {
    final now = DateTime.now().toUtc();
    final snapshot = ContextFixtures.lakeSunset(observedAt: now);
    final store = InMemoryContextEntryStore();
    final controller = PartialRefreshController(entryStore: store);
    final sessionEntry = ContextEntryAdapter.fromShootingSession(
      snapshot.shootingSessions.single,
      observedAt: now,
    );

    final first = controller.apply(
      EnvironmentSliceBatch(
        transactionId: 'tx-1',
        reason: 'initial',
        slices: {EnvironmentSliceKey.scene: _slice(snapshot, now, 1)},
        entries: EntryBatch(entries: [sessionEntry], sourceRevision: 1),
      ),
    );
    expect(first.addedEntries, hasLength(1));

    final second = controller.apply(
      EnvironmentSliceBatch(
        transactionId: 'tx-2',
        reason: 'weather',
        slices: {EnvironmentSliceKey.weather: _slice(snapshot, now, 2)},
        entries: const EntryBatch(entries: [], sourceRevision: 2),
      ),
    );
    expect(second.changedSlices, contains(EnvironmentSliceKey.weather));
    expect(controller.state!.entries.value, hasLength(1));
    expect(controller.state!.entries.value.single.id, sessionEntry.id);
  });
}

StateSlice<Object?> _slice(Object value, DateTime now, int revision) {
  return StateSlice<Object?>(
    value: value,
    revision: revision,
    observedAt: now,
    expiresAt: now.add(const Duration(minutes: 10)),
    freshness: SliceFreshness.fresh,
    sourceFingerprint: '$revision',
  );
}
