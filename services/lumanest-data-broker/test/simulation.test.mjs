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
  registry.register('abcde12345678', { contractVersion: 5 });
  const [session] = registry.list();
  assert.equal(session.sessionCode, '12345678');
  assert.match(session.controlId, /^sim_[a-f0-9]{24}$/);
  assert.equal(session.contractVersion, 5);
  assert.equal(registry.activate(session.controlId, 'lake-sunset').ok, true);
  assert.equal(registry.snapshot('abcde12345678', new Date(0)).environment.scene, 'lake');
  assert.equal(registry.list()[0].deliveryCount, 1);
  assert.deepEqual(registry.clearAll(), { ok: true, cleared: 1 });
  now += 101;
  assert.deepEqual(registry.list(), []);
});

test('presets produce a complete current context snapshot', () => {
  const snapshot = simulatedSnapshot('rain-thunder', new Date('2026-07-17T00:00:00.000Z'));
  assert.equal(snapshot.contractVersion, 5);
  assert.equal(snapshot.environment.weather.condition, 'rain');
  assert.equal(snapshot.facts.events.some((event) => event.id === 'thunderstorm'), true);
  assert.equal(snapshot.entries.some((entry) => entry.kind === 'safety'), true);
  assert.equal(snapshot.environment.sceneContext.activity, 'hiking');
  assert.equal(snapshot.facts.shootingSessions.length, 1);
  assert.equal(snapshot.facts.shootingSessions[0].conditionBand, 'limited');
  assert.equal(snapshot.facts.shootingSessions[0].targetCandidates.length, 0);
  assert.equal(snapshot.facts.shootingSessions[0].phases.some((phase) => phase.kind === 'safeStop'), true);
  assert.equal(simulationPresetCatalog().length, 6);
  assert.equal(simulationPresetCatalog().some((preset) => preset.hasSafetyAlert), true);
  assert.equal(simulatedSnapshot('unknown'), null);
});
