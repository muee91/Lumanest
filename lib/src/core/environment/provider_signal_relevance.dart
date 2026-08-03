import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/environment/provider_facts.dart';

/// Selects the small set of supplementary signals that matters in the current
/// scene. This does not change evidence strength or promote a provider into the
/// authoritative Context safety chain.
List<ProviderSignal> selectProviderSignalsForContext(
  ProviderFactsBundle bundle,
  ContextSnapshot snapshot, {
  DateTime? now,
  int maximum = 4,
}) {
  if (maximum < 1 || maximum > 8) {
    throw RangeError.range(maximum, 1, 8, 'maximum');
  }
  final current = bundle.displayableSignalsAt(now ?? DateTime.now().toUtc());
  if (current.isEmpty) return const <ProviderSignal>[];

  final priorities = _categoryPriorities(snapshot);
  final ranked = [...current]..sort((a, b) {
    final aAuthoritative =
        a.verification == ProviderVerification.authoritative;
    final bAuthoritative =
        b.verification == ProviderVerification.authoritative;
    if (aAuthoritative != bAuthoritative) return aAuthoritative ? -1 : 1;

    final relevance = (priorities[a.category] ?? 99).compareTo(
      priorities[b.category] ?? 99,
    );
    if (relevance != 0) return relevance;

    final evidence = _authorityRank(a.verification).compareTo(
      _authorityRank(b.verification),
    );
    if (evidence != 0) return evidence;
    return b.observedAt.compareTo(a.observedAt);
  });

  final selected = <ProviderSignal>[];
  final kinds = <String>{};
  final categories = <ProviderCategory>{};
  for (final signal in ranked) {
    final authoritative =
        signal.verification == ProviderVerification.authoritative;
    if (!authoritative &&
        (kinds.contains(signal.kind) || categories.contains(signal.category))) {
      continue;
    }
    selected.add(signal);
    kinds.add(signal.kind);
    categories.add(signal.category);
    if (selected.length == maximum) break;
  }

  // Sparse locations may only have multiple signals from one category. Fill
  // the remaining slots rather than hiding useful, current evidence.
  if (selected.length < maximum) {
    for (final signal in ranked) {
      if (selected.any((item) => item.id == signal.id)) continue;
      selected.add(signal);
      if (selected.length == maximum) break;
    }
  }
  return List.unmodifiable(selected);
}

Map<ProviderCategory, int> _categoryPriorities(ContextSnapshot snapshot) {
  final ordered = <ProviderCategory>[];
  void add(Iterable<ProviderCategory> values) {
    for (final value in values) {
      if (!ordered.contains(value)) ordered.add(value);
    }
  }

  if (snapshot.routeStage != ContextRouteStage.none) {
    add(const [
      ProviderCategory.operations,
      ProviderCategory.outdoor,
      ProviderCategory.fire,
      ProviderCategory.atmosphere,
    ]);
  }

  switch (snapshot.primaryScene) {
    case SceneType.mountain:
      add(const [
        ProviderCategory.operations,
        ProviderCategory.surface,
        ProviderCategory.atmosphere,
        ProviderCategory.outdoor,
        ProviderCategory.fire,
      ]);
    case SceneType.desert:
      add(const [
        ProviderCategory.atmosphere,
        ProviderCategory.fire,
        ProviderCategory.surface,
        ProviderCategory.operations,
        ProviderCategory.outdoor,
      ]);
    case SceneType.lake:
      add(const [
        ProviderCategory.surface,
        ProviderCategory.atmosphere,
        ProviderCategory.operations,
        ProviderCategory.outdoor,
        ProviderCategory.wildlife,
        ProviderCategory.marine,
      ]);
    case SceneType.village:
      add(const [
        ProviderCategory.operations,
        ProviderCategory.culture,
        ProviderCategory.outdoor,
        ProviderCategory.atmosphere,
        ProviderCategory.wildlife,
      ]);
    case SceneType.city:
      add(const [
        ProviderCategory.operations,
        ProviderCategory.culture,
        ProviderCategory.atmosphere,
        ProviderCategory.outdoor,
      ]);
    case SceneType.unknown:
      add(const [
        ProviderCategory.operations,
        ProviderCategory.atmosphere,
        ProviderCategory.surface,
        ProviderCategory.outdoor,
        ProviderCategory.culture,
      ]);
  }

  if (snapshot.dayPhase == DayPhase.night ||
      snapshot.dayPhase == DayPhase.blueHour) {
    add(const [
      ProviderCategory.astronomy,
      ProviderCategory.spaceWeather,
    ]);
  }

  add(ProviderCategory.values);
  return {
    for (var index = 0; index < ordered.length; index++) ordered[index]: index,
  };
}

int _authorityRank(ProviderVerification verification) => switch (verification) {
  ProviderVerification.authoritative => 0,
  ProviderVerification.observed => 1,
  ProviderVerification.model => 2,
  ProviderVerification.reference => 3,
  ProviderVerification.candidate => 4,
};
