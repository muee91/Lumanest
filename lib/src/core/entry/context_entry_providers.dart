import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/entry/context_entry_store.dart';

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
