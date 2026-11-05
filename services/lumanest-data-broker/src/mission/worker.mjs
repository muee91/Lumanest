import { randomBytes } from 'node:crypto';

import { apiErrorCodes } from '../api/error-codes.mjs';
import { MissionStore } from './store.mjs';

function workerId() {
  return `mission-worker-${process.pid}-${randomBytes(6).toString('hex')}`;
}

function validSnapshot(value) {
  return value != null && typeof value === 'object' &&
    typeof value.contextId === 'string' && /^ctx_[a-f0-9]{24}$/.test(value.contextId) &&
    typeof value.generatedAt === 'string' && Array.isArray(value.facts?.events);
}

function contextRequest(mission, observedAt) {
  return {
    contractVersion: 5,
    coordinate: {
      latitude: mission.destination.latitude,
      longitude: mission.destination.longitude,
      system: mission.destination.system,
    },
    observedAt: observedAt.toISOString(),
    locale: mission.locale,
    intent: mission.intent,
    route: {
      mode: 'none',
      stage: 'none',
      routeId: null,
      corridorSamples: [],
    },
  };
}

function missionEvents(snapshot) {
  return snapshot.facts.events
    .filter((event) => event != null && typeof event.id === 'string')
    .slice(0, 32)
    .map((event) => ({
      dedupeKey: `${event.id}:${event.expiresAt ?? 'none'}`,
      kind: event.channel ?? 'context',
      source: event.source ?? 'rule',
      observedAt: event.observedAt ?? snapshot.generatedAt,
      expiresAt: event.expiresAt ?? null,
      payload: {
        id: event.id,
        title: event.title ?? null,
        severity: event.severity ?? 'info',
        allowedAction: event.allowedAction ?? 'dismiss',
      },
    }));
}

export class MissionWorker {
  constructor({
    store,
    brokerUrl,
    workerToken,
    fetcher = fetch,
    now = () => new Date(),
    id = workerId(),
  }) {
    this.store = store;
    this.brokerUrl = brokerUrl;
    this.workerToken = workerToken;
    this.fetcher = fetcher;
    this.now = now;
    this.id = id;
  }

  async runOnce() {
    const claimed = await this.store.claimDue({ workerId: this.id, now: this.now() });
    if (!claimed.ok || claimed.mission == null) return claimed;
    const mission = claimed.mission;
    const startedAt = this.now();
    let check = { ok: false, startedAt, error: apiErrorCodes.notConfigured };
    let events = [];
    if (this.brokerUrl && this.workerToken) {
      try {
        const upstream = await this.fetcher(new URL('/internal/v1/mission/check', this.brokerUrl), {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Mission-Worker-Token': this.workerToken,
          },
          body: JSON.stringify(contextRequest(mission, startedAt)),
          signal: AbortSignal.timeout(20_000),
        });
        const body = await upstream.json();
        if (!upstream.ok) {
          check = { ok: false, startedAt, error: typeof body?.error === 'string' ? body.error : 'upstream_unavailable' };
        } else if (!validSnapshot(body)) {
          check = { ok: false, startedAt, error: apiErrorCodes.upstreamContractMismatch };
        } else {
          check = { ok: true, startedAt, contextId: body.contextId };
          events = missionEvents(body);
        }
      } catch {
        check = { ok: false, startedAt, error: apiErrorCodes.upstreamUnavailable };
      }
    }
    return this.store.finishCheck({
      mission,
      workerId: this.id,
      check,
      events,
      now: this.now(),
    });
  }
}

export async function runMissionWorker(environment = process.env) {
  const store = new MissionStore({
    connectionString: environment.MISSION_WORKER_DATABASE_URL?.trim() ?? '',
  });
  if (!store.configured) throw new Error('MISSION_WORKER_DATABASE_URL is required');
  const worker = new MissionWorker({
    store,
    brokerUrl: environment.MISSION_BROKER_URL?.trim() ?? '',
    workerToken: environment.MISSION_WORKER_TOKEN?.trim() ?? '',
  });
  let stopping = false;
  const stop = () => { stopping = true; };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
  try {
    while (!stopping) {
      await worker.runOnce();
      await new Promise((resolve) => setTimeout(resolve, 1_000));
    }
  } finally {
    await store.close();
  }
}
