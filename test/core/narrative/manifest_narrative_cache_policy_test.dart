import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_coordinator.dart';

void main() {
  test('tone is part of the narrative cache identity', () async {
    final now = DateTime.utc(2026, 7, 20, 10);
    final snapshot = ContextFixtures.lakeSunset(observedAt: now);
    final manifest = ManifestPolicy.build(snapshot, now: now);
    final model = _CountingModel();
    final coordinator = ManifestNarrativeCoordinator(
      model: model,
      now: () => now,
    );

    await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
      tone: NarrativeTone.concise,
      preferenceFingerprint: 'same-preference',
    );
    await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
      tone: NarrativeTone.detailed,
      preferenceFingerprint: 'same-preference',
    );
    await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
      tone: NarrativeTone.concise,
      preferenceFingerprint: 'same-preference',
    );

    expect(model.calls, 2);
    expect(model.tones, [NarrativeTone.concise, NarrativeTone.detailed]);
  });

  test('a new observed batch never reuses an older narrative', () async {
    var clock = DateTime.utc(2026, 7, 20, 10);
    final firstSnapshot = ContextFixtures.lakeSunset(observedAt: clock);
    final secondSnapshot = ContextFixtures.lakeSunset(
      observedAt: clock.add(const Duration(minutes: 2)),
    );
    final model = _CountingModel();
    final coordinator = ManifestNarrativeCoordinator(
      model: model,
      now: () => clock,
    );

    await coordinator.resolve(
      snapshot: firstSnapshot,
      manifest: ManifestPolicy.build(firstSnapshot, now: clock),
    );
    clock = clock.add(const Duration(minutes: 2));
    await coordinator.resolve(
      snapshot: secondSnapshot,
      manifest: ManifestPolicy.build(secondSnapshot, now: clock),
    );

    expect(model.calls, 2);
  });

  test('model failures back off briefly and recover without a long template cache', () async {
    var clock = DateTime.utc(2026, 7, 20, 10);
    final snapshot = ContextFixtures.lakeSunset(observedAt: clock);
    final manifest = ManifestPolicy.build(snapshot, now: clock);
    final model = _RecoveringModel();
    final coordinator = ManifestNarrativeCoordinator(
      model: model,
      now: () => clock,
      failureBackoff: const Duration(minutes: 1),
    );

    final first = await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
    );
    final duringBackoff = await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
    );
    clock = clock.add(const Duration(seconds: 61));
    final recovered = await coordinator.resolve(
      snapshot: snapshot,
      manifest: manifest,
    );

    expect(first.source, ManifestNarrativeSource.template);
    expect(duringBackoff.source, ManifestNarrativeSource.template);
    expect(recovered.source, ManifestNarrativeSource.model);
    expect(model.calls, 2);
  });
}

class _CountingModel implements ManifestNarrativeModel {
  var calls = 0;
  final tones = <NarrativeTone>[];

  @override
  Future<ManifestNarrativeCandidate> generate(
    ManifestNarrativeRequest request,
  ) async {
    calls += 1;
    tones.add(request.tone);
    return ManifestNarrativeCandidate(
      summary: request.tone == NarrativeTone.detailed
          ? '湖面正在安静下来，可以继续观察倒影。'
          : '湖面渐静，继续观察。',
      noteLabels: {
        for (final id in request.creativeEventIds) id: '等倒影',
      },
    );
  }
}

class _RecoveringModel implements ManifestNarrativeModel {
  var calls = 0;

  @override
  Future<ManifestNarrativeCandidate> generate(
    ManifestNarrativeRequest request,
  ) async {
    calls += 1;
    if (calls == 1) throw StateError('temporary failure');
    return ManifestNarrativeCandidate(
      summary: '湖面渐静，继续观察。',
      noteLabels: {
        for (final id in request.creativeEventIds) id: '等倒影',
      },
    );
  }
}
