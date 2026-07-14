import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_coordinator.dart';

void main() {
  final now = DateTime.utc(2026, 7, 11, 10, 5);
  final snapshot = ContextFixtures.lakeSunset();
  final manifest = ManifestPolicy.build(snapshot, now: now);

  test(
    'model request contains context categories but no coordinates',
    () async {
      final model = _FakeModel(
        const ManifestNarrativeCandidate(
          summary: '湖面正在安静下来，可以等等倒影。',
          noteLabels: {'reflection': '等倒影'},
        ),
      );
      final coordinator = ManifestNarrativeCoordinator(
        model: model,
        now: () => now,
      );

      await coordinator.resolve(snapshot: snapshot, manifest: manifest);

      expect(model.requests.single.scene, snapshot.primaryScene);
      expect(model.requests.single.creativeEventIds, [
        'reflection',
        'blue-hour',
      ]);
      expect(model.requests.single.toString(), isNot(contains('latitude')));
      expect(model.requests.single.toString(), isNot(contains('longitude')));
    },
  );

  test(
    'accepts copy only for creative events already in the manifest',
    () async {
      final coordinator = ManifestNarrativeCoordinator(
        model: _FakeModel(
          const ManifestNarrativeCandidate(
            summary: '湖面正在安静下来，可以等等倒影。',
            noteLabels: {'reflection': '等倒影', 'blue-hour': '等蓝调'},
          ),
        ),
        now: () => now,
      );

      final narrative = await coordinator.resolve(
        snapshot: snapshot,
        manifest: manifest,
      );

      expect(narrative.source, ManifestNarrativeSource.model);
      expect(narrative.summary, '湖面正在安静下来，可以等等倒影。');
      expect(narrative.noteLabels['reflection'], '等倒影');
    },
  );

  test('rejects unknown events and falls back to deterministic copy', () async {
    final coordinator = ManifestNarrativeCoordinator(
      model: _FakeModel(
        const ManifestNarrativeCandidate(
          summary: '附近一定有猛兽，立即前往。',
          noteLabels: {'invented-event': '追过去'},
        ),
      ),
      now: () => now,
    );

    final narrative = await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
    );

    expect(narrative.source, ManifestNarrativeSource.template);
    expect(narrative.summary, manifest.summary);
    expect(narrative.noteLabels, isEmpty);
  });

  test(
    'model failure and stale snapshots use the template without throwing',
    () async {
      final failing = _ThrowingModel();
      final coordinator = ManifestNarrativeCoordinator(
        model: failing,
        now: () => now,
      );

      final failed = await coordinator.resolve(
        snapshot: snapshot,
        manifest: manifest,
      );
      final staleSnapshot = snapshot.asStale();
      final stale = await coordinator.resolve(
        snapshot: staleSnapshot,
        manifest: ManifestPolicy.build(staleSnapshot, now: now),
      );

      expect(failed.source, ManifestNarrativeSource.template);
      expect(stale.source, ManifestNarrativeSource.template);
      expect(
        failing.calls,
        1,
        reason: 'stale facts must not be sent to a model',
      );
    },
  );

  test(
    'deduplicates simultaneous requests and reuses unexpired cache',
    () async {
      final completer = Completer<ManifestNarrativeCandidate>();
      final model = _CompletingModel(completer.future);
      final coordinator = ManifestNarrativeCoordinator(
        model: model,
        now: () => now,
      );

      final first = coordinator.resolve(snapshot: snapshot, manifest: manifest);
      final second = coordinator.resolve(
        snapshot: snapshot,
        manifest: manifest,
      );
      expect(model.calls, 1);
      completer.complete(
        const ManifestNarrativeCandidate(
          summary: '风停下来时，倒影会更完整。',
          noteLabels: {'reflection': '等风停'},
        ),
      );

      expect(await first, await second);
      await coordinator.resolve(snapshot: snapshot, manifest: manifest);
      expect(model.calls, 1);
    },
  );

  test(
    'preference fingerprint isolates cache and tone reaches the model',
    () async {
      final model = _FakeModel(
        const ManifestNarrativeCandidate(summary: '湖面正在安静下来，可以等等倒影。'),
      );
      final coordinator = ManifestNarrativeCoordinator(
        model: model,
        now: () => now,
      );

      await coordinator.resolve(
        snapshot: snapshot,
        manifest: manifest,
        tone: NarrativeTone.concise,
        preferenceFingerprint: 'preference-a',
      );
      await coordinator.resolve(
        snapshot: snapshot,
        manifest: manifest,
        tone: NarrativeTone.concise,
        preferenceFingerprint: 'preference-a',
      );
      await coordinator.resolve(
        snapshot: snapshot,
        manifest: manifest,
        tone: NarrativeTone.detailed,
        preferenceFingerprint: 'preference-b',
      );

      expect(model.requests, hasLength(2));
      expect(model.requests.first.tone, NarrativeTone.concise);
      expect(model.requests.last.tone, NarrativeTone.detailed);
      expect(model.requests.first.toString(), isNot(contains('preference-a')));
      expect(model.requests.last.toString(), isNot(contains('detailed')));
    },
  );
}

class _FakeModel implements ManifestNarrativeModel {
  _FakeModel(this.candidate);
  final ManifestNarrativeCandidate candidate;
  final requests = <ManifestNarrativeRequest>[];

  @override
  Future<ManifestNarrativeCandidate> generate(
    ManifestNarrativeRequest request,
  ) async {
    requests.add(request);
    return candidate;
  }
}

class _ThrowingModel implements ManifestNarrativeModel {
  var calls = 0;

  @override
  Future<ManifestNarrativeCandidate> generate(
    ManifestNarrativeRequest request,
  ) async {
    calls += 1;
    throw StateError('model unavailable');
  }
}

class _CompletingModel implements ManifestNarrativeModel {
  _CompletingModel(this.result);
  final Future<ManifestNarrativeCandidate> result;
  var calls = 0;

  @override
  Future<ManifestNarrativeCandidate> generate(
    ManifestNarrativeRequest request,
  ) {
    calls += 1;
    return result;
  }
}
