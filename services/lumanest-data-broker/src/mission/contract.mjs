const missionIntents = new Set(['photography', 'food', 'supplies', 'fuel', 'wildlife']);
const missionStates = new Set(['planning', 'enRoute', 'field', 'completed', 'cancelled']);
const missionOperations = new Set(['start', 'arrive', 'complete', 'cancel', 'setWatch', 'updateDestination']);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return object(value) && Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

function validTimestamp(value) {
  return value == null || (
    typeof value === 'string' && value.length <= 40 && Number.isFinite(Date.parse(value))
  );
}

function validDestination(value) {
  return exactKeys(value, new Set(['name', 'latitude', 'longitude', 'system'])) &&
    typeof value.name === 'string' && [...value.name.trim()].length >= 1 &&
    [...value.name.trim()].length <= 200 &&
    typeof value.latitude === 'number' && Number.isFinite(value.latitude) &&
    value.latitude >= -90 && value.latitude <= 90 &&
    typeof value.longitude === 'number' && Number.isFinite(value.longitude) &&
    value.longitude >= -180 && value.longitude <= 180 &&
    value.system === 'wgs84';
}

export function validMissionCreateRequest(value) {
  return exactKeys(value, new Set([
    'destination', 'intent', 'locale', 'startsAt', 'endsAt', 'watchEnabled',
  ])) && validDestination(value.destination) && missionIntents.has(value.intent) &&
    ['zh-CN', 'en'].includes(value.locale) && validTimestamp(value.startsAt) &&
    validTimestamp(value.endsAt) &&
    (value.startsAt == null || value.endsAt == null || Date.parse(value.startsAt) <= Date.parse(value.endsAt)) &&
    typeof value.watchEnabled === 'boolean';
}

export function validMissionPatchRequest(value) {
  if (!exactKeys(value, new Set(['expectedVersion', 'operation', 'watchEnabled', 'destination']))) {
    return false;
  }
  if (!Number.isInteger(value.expectedVersion) || value.expectedVersion < 1 ||
      !missionOperations.has(value.operation)) return false;
  if (value.operation === 'setWatch') {
    return typeof value.watchEnabled === 'boolean' && value.destination == null;
  }
  if (value.operation === 'updateDestination') {
    return value.watchEnabled == null && validDestination(value.destination);
  }
  return value.watchEnabled == null && value.destination == null;
}

export function isMissionState(value) {
  return missionStates.has(value);
}

export function missionResponse(row) {
  if (row == null) return null;
  return {
    id: row.id,
    state: row.state,
    destination: row.destination,
    intent: row.intent,
    locale: row.locale,
    watchEnabled: row.watch_enabled,
    startsAt: row.starts_at == null ? null : new Date(row.starts_at).toISOString(),
    endsAt: row.ends_at == null ? null : new Date(row.ends_at).toISOString(),
    version: row.version,
    nextCheckAt: row.next_check_at == null ? null : new Date(row.next_check_at).toISOString(),
    lastCheckedAt: row.last_checked_at == null ? null : new Date(row.last_checked_at).toISOString(),
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString(),
  };
}

export function missionEventResponse(row) {
  return {
    id: row.id,
    missionId: row.mission_id,
    dedupeKey: row.dedupe_key,
    kind: row.kind,
    source: row.source,
    observedAt: new Date(row.observed_at).toISOString(),
    expiresAt: row.expires_at == null ? null : new Date(row.expires_at).toISOString(),
    payload: row.payload,
    deliveryState: row.delivered_at == null ? 'not_sent' : 'sent',
    createdAt: new Date(row.created_at).toISOString(),
  };
}

export const missionStateTransitions = Object.freeze({
  start: ['planning', 'enRoute'],
  arrive: ['enRoute', 'field'],
  complete: ['field', 'completed'],
  cancel: ['planning', 'cancelled'],
});
