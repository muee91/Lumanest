import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';
import 'package:luma_nest/src/core/entry/entry_action.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/entry/entry_provenance.dart';

void main() {
  test('applies one atomic delta and rejects an older revision', () {
    final now = DateTime.now().toUtc();
    final store = InMemoryContextEntryStore();
    final first = _entry(revision: 10, now: now, title: '第一版');
    final firstDelta = store.apply(
      EntryBatch(entries: [first], sourceRevision: 10),
    );

    expect(firstDelta.added.single.id, first.id);
    expect(store.current.revision, 10);

    final older = _entry(revision: 9, now: now, title: '旧版本');
    final olderDelta = store.apply(
      EntryBatch(entries: [older], sourceRevision: 11),
    );
    expect(olderDelta.updated, isEmpty);
    expect(store.byId(first.id)!.presentation.title, '第一版');

    final newer = _entry(revision: 12, now: now, title: '新版');
    final newerDelta = store.apply(
      EntryBatch(entries: [newer], sourceRevision: 12),
    );
    expect(newerDelta.updated.single.presentation.title, '新版');
    expect(store.current.revision, 12);
  });
}

ContextEntry _entry({
  required int revision,
  required DateTime now,
  required String title,
}) {
  return ContextEntry(
    id: 'entry_test_same',
    kind: EntryKind.photographyOpportunity,
    sourceNamespace: 'test',
    sourceId: 'source',
    revision: revision,
    observedAt: now,
    validFrom: now,
    expiresAt: now.add(const Duration(hours: 1)),
    freshness: EntryFreshness.fresh,
    evidenceConfidence: .7,
    basePriority: EntryPriority.p1,
    severity: EntrySeverity.info,
    geoScope: const EntryGeoScope(type: ContextGeoScope.region),
    allowedSurfaces: const {EntrySurface.today},
    actions: const [EntryAction(type: EntryActionType.openExplore)],
    presentation: EntryPresentation(
      variant: EntryPresentationVariant.manifestOpportunity,
      eyebrow: '测试',
      title: title,
      detail: '详情',
      timeLabel: '现在',
      actionLabel: '查看',
      accent: EntryAccent.sky,
    ),
    payload: const SystemEntryPayload(stateCode: 'test'),
    provenance: [EntryProvenance(sourceId: 'test', observedAt: now)],
    dedupeKey: 'test',
    contentFingerprint: title,
  );
}
