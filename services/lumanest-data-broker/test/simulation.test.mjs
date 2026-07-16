import assert from 'node:assert/strict';
import test from 'node:test';

import { SimulationRegistry, simulatedSnapshot } from '../src/context/simulation.mjs';

test('simulation registry keeps only short-lived anonymous sessions', () => {
  let now = 1_000;
  const registry = new SimulationRegistry({ now: () => now, ttlMs: 100 });
  registry.register('abcde12345678');
  assert.deepEqual(registry.list().map((item) => item.sessionCode), ['12345678']);
  assert.equal(registry.activate('12345678', 'lake-sunset').ok, true);
  assert.equal(registry.snapshot('abcde12345678', new Date(0)).scene, 'lake');
  now += 101;
  assert.deepEqual(registry.list(), []);
});

test('presets produce a complete safe v2-shaped context snapshot', () => {
  const snapshot = simulatedSnapshot('rain-thunder', new Date('2026-07-17T00:00:00.000Z'));
  assert.equal(snapshot.contractVersion, 2);
  assert.equal(snapshot.weather.condition, 'rain');
  assert.equal(snapshot.events.some((event) => event.id === 'thunderstorm'), true);
  assert.equal(snapshot.manifest.primaryEventId, 'mist');
  assert.equal(simulatedSnapshot('unknown'), null);
});
