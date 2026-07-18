import assert from 'node:assert/strict';
import test from 'node:test';

import {
  SimulationRegistry,
  simulatedSnapshot,
  simulationPresetCatalog,
} from '../src/context/simulation.mjs';

test('simulation registry keeps only short-lived anonymous sessions', () => {
  let now = 1_000;
  const registry = new SimulationRegistry({ now: () => now, ttlMs: 100 });
  registry.register('abcde12345678', { contractVersion: 4 });
  const [session] = registry.list();
  assert.equal(session.sessionCode, '12345678');
  assert.match(session.controlId, /^sim_[a-f0-9]{24}$/);
  assert.equal(session.contractVersion, 4);
  assert.equal(registry.activate(session.controlId, 'lake-sunset').ok, true);
  assert.equal(registry.snapshot('abcde12345678', new Date(0)).scene, 'lake');
  assert.equal(registry.suppressFeedback('abcde12345678'), true);
  assert.equal(registry.list()[0].deliveryCount, 1);
  assert.equal(registry.list()[0].suppressedFeedbackCount, 1);
  assert.deepEqual(registry.clearAll(), { ok: true, cleared: 1 });
  assert.equal(registry.suppressFeedback('abcde12345678'), false);
  now += 101;
  assert.deepEqual(registry.list(), []);
});

test('presets produce a complete current context snapshot', () => {
  const snapshot = simulatedSnapshot('rain-thunder', new Date('2026-07-17T00:00:00.000Z'));
  assert.equal(snapshot.contractVersion, 4);
  assert.equal(snapshot.weather.condition, 'rain');
  assert.equal(snapshot.events.some((event) => event.id === 'thunderstorm'), true);
  assert.equal(snapshot.manifest.primaryEventId, 'session.mountain.morning');
  assert.equal(snapshot.sceneContext.activity, 'hiking');
  assert.equal(snapshot.opportunityCatalogVersion, 1);
  assert.equal(snapshot.shootingSessions.length, 1);
  assert.equal(snapshot.shootingSessions[0].conditionBand, 'limited');
  assert.equal(snapshot.shootingSessions[0].targetCandidates.length, 0);
  assert.equal(snapshot.shootingSessions[0].phases.some((phase) => phase.kind === 'safeStop'), true);
  assert.equal(simulationPresetCatalog().length, 6);
  assert.equal(simulationPresetCatalog().some((preset) => preset.hasSafetyAlert), true);
  assert.equal(simulatedSnapshot('unknown'), null);
});
