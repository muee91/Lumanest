import { createHash } from 'node:crypto';

import {
  creativePrompts,
  opportunityCatalog,
} from '../generated/opportunity-catalog.mjs';

const refreshReasons = new Set([
  'region_changed', 'route_created', 'route_started', 'time_phase_changed',
  'dwell_reached', 'manual_refresh', 'opportunity_changed',
]);
const visiblePages = new Set(['today', 'explore', 'route', 'inspiration', 'profile', 'shootingWindow']);
const feedbackActions = new Set([
  'viewed', 'dismissed', 'saved', 'routed', 'started', 'completed', 'not_interested',
]);
const inventoryChannels = new Set([
  'photographyOpportunity', 'localDiscovery', 'humanityClue', 'creativePrompt',
  'routeCompanion', 'lifeCompanion', 'memoryFollowUp', 'wildlifeOpportunity',
]);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function exactKeys(value, keys) {
  return object(value) && Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

export function validIdempotencyKey(value) {
  return typeof value === 'string' && /^[A-Za-z0-9._:-]{8,128}$/.test(value);
}

export function validCompanionRefreshRequest(value) {
  return exactKeys(value, new Set([
    'snapshotId', 'reason', 'routeId', 'visiblePage', 'localTimeZone',
  ])) && typeof value.snapshotId === 'string' && /^ctx_[a-f0-9]{24}$/.test(value.snapshotId) &&
    refreshReasons.has(value.reason) &&
    (value.routeId == null || (typeof value.routeId === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value.routeId))) &&
    visiblePages.has(value.visiblePage) &&
    typeof value.localTimeZone === 'string' && /^[A-Za-z_]+(?:\/[A-Za-z0-9_+.-]+)+$/.test(value.localTimeZone);
}

export function validInsightFeedbackRequest(value) {
  return exactKeys(value, new Set(['action'])) && feedbackActions.has(value.action);
}

function stableId(prefix, ...parts) {
  const digest = createHash('sha256').update(parts.join('\0')).digest('hex').slice(0, 24);
  return `${prefix}_${digest}`;
}

function definitionForEvent(eventId) {
  return opportunityCatalog.find((item) => item.id === eventId) ?? null;
}

function sourceForEvent(event) {
  return Object.freeze({
    id: event.source,
    label: event.source === 'official' ? '权威来源' : '结构化环境数据',
    observedAt: event.observedAt,
    ...(event.sourceUrl == null ? {} : { url: event.sourceUrl }),
  });
}

function eventInsight(event, snapshot) {
  const definition = definitionForEvent(event.id);
  if (event.channel === 'safety' || event.channel === 'wildlifeSafety') return null;
  const wildlife = event.channel === 'wildlifeOpportunity';
  const presentation = definition?.presentation?.zhCN;
  const action = definition?.primaryAction ?? event.allowedAction;
  const channel = wildlife ? 'wildlifeOpportunity' : 'photographyOpportunity';
  return Object.freeze({
    id: stableId('insight', snapshot.contextId, event.id, event.observedAt),
    channel,
    title: presentation?.name ?? event.title ?? (wildlife ? '附近生态线索' : '环境机会'),
    body: presentation?.fallbackSummary ?? (wildlife
      ? '附近存在区域级历史生态信号，只作为观察线索。'
      : '这条机会来自当前结构化环境事实。'),
    shortLabel: presentation?.shortLabel ?? (wildlife ? '生态线索' : '环境机会'),
    emoji: presentation?.emoji ?? (wildlife ? '🦅' : '📷'),
    generatedAt: snapshot.generatedAt,
    startsAt: event.observedAt,
    peaksAt: null,
    expiresAt: event.expiresAt,
    geoScope: event.geoScope,
    confidence: event.confidence,
    priority: wildlife ? 45 : 70,
    action,
    sources: [sourceForEvent(event)],
    canEnterBottle: true,
    canNotify: false,
    opportunityInstanceId: definition == null
      ? null
      : stableId('opportunity', snapshot.contextId, definition.id, event.observedAt),
    targetId: null,
    routeId: snapshot.route?.active ? snapshot.route.routeId ?? null : null,
    sessionId: null,
    searchMissionId: null,
  });
}

function creativeInsight(prompt, snapshot, generatedAt) {
  const expiresAt = new Date(generatedAt.getTime() + prompt.cooldownHours * 3_600_000).toISOString();
  return Object.freeze({
    id: stableId('insight', snapshot.contextId, prompt.id, generatedAt.toISOString().slice(0, 10)),
    channel: 'creativePrompt',
    title: prompt.shortLabel,
    body: prompt.guide,
    shortLabel: prompt.shortLabel,
    emoji: '📝',
    generatedAt: generatedAt.toISOString(),
    startsAt: generatedAt.toISOString(),
    peaksAt: null,
    expiresAt,
    geoScope: 'region',
    confidence: 1,
    priority: 30,
    action: 'openCreativeDetail',
    sources: [],
    canEnterBottle: true,
    canNotify: false,
    opportunityInstanceId: null,
    targetId: null,
    routeId: null,
    sessionId: null,
    searchMissionId: null,
  });
}

function seededCreative(snapshot, generatedAt, limit) {
  const date = generatedAt.toISOString().slice(0, 10);
  return creativePrompts
    .map((prompt) => ({
      prompt,
      order: createHash('sha256').update(`${snapshot.contextId}\0${date}\0${prompt.id}`).digest('hex'),
    }))
    .sort((left, right) => left.order.localeCompare(right.order))
    .slice(0, limit)
    .map(({ prompt }) => creativeInsight(prompt, snapshot, generatedAt));
}

function visibleInsights(snapshot) {
  return (snapshot.facts?.events ?? [])
    .map((event) => eventInsight(event, snapshot))
    .filter(Boolean)
    .filter((insight) => Number.isFinite(Date.parse(insight.expiresAt)));
}

export class CompanionStore {
  constructor({ now = () => new Date() } = {}) {
    this.now = now;
    this.snapshots = new Map();
    this.inventory = [];
    this.refreshReceipts = new Map();
    this.feedbackReceipts = new Map();
  }

  rememberSnapshot(snapshot) {
    if (!object(snapshot) || typeof snapshot.contextId !== 'string') return;
    this.snapshots.set(snapshot.contextId, Object.freeze(structuredClone(snapshot)));
    while (this.snapshots.size > 24) this.snapshots.delete(this.snapshots.keys().next().value);
  }

  snapshot(contextId) {
    return this.snapshots.get(contextId) ?? null;
  }

  refresh(request, idempotencyKey) {
    if (this.refreshReceipts.has(idempotencyKey)) return this.refreshReceipts.get(idempotencyKey);
    const snapshot = this.snapshots.get(request.snapshotId);
    if (snapshot == null) return Object.freeze({ ok: false, error: 'invalid_snapshot' });
    const generatedAt = this.now();
    const factual = visibleInsights(snapshot);
    const creative = seededCreative(snapshot, generatedAt, 36);
    const candidates = [...factual, ...creative]
      .filter((insight) => insight.channel !== 'safety' && insight.canEnterBottle)
      .sort((left, right) => right.priority - left.priority || left.id.localeCompare(right.id))
      .slice(0, 60);
    const priorIds = new Set(this.inventory.map((item) => item.id));
    this.inventory = Object.freeze(candidates);
    const result = Object.freeze({
      ok: true,
      status: 200,
      body: Object.freeze({
        primaryInsight: factual[0] ?? null,
        secondaryInsights: factual.slice(1, 3),
        inventoryDelta: Object.freeze({
          added: candidates.filter((item) => !priorIds.has(item.id)).slice(0, 20),
          expiredIds: [...priorIds].filter((id) => !candidates.some((item) => item.id === id)),
        }),
        nextRefreshAt: new Date(generatedAt.getTime() + 30 * 60_000).toISOString(),
        partial: false,
      }),
    });
    this.refreshReceipts.set(idempotencyKey, result);
    return result;
  }

  listInventory({ cursor = 0, limit = 36, channels = null } = {}) {
    const filtered = channels == null
      ? this.inventory
      : this.inventory.filter((item) => channels.has(item.channel));
    const items = filtered.slice(cursor, cursor + limit);
    const next = cursor + items.length;
    return Object.freeze({
      targetSize: 36,
      minimumSize: 20,
      maximumSize: 60,
      items,
      nextCursor: next < filtered.length ? String(next) : null,
    });
  }

  feedback(insightId, action, idempotencyKey) {
    const receiptKey = `${insightId}:${idempotencyKey}`;
    if (this.feedbackReceipts.has(receiptKey)) return this.feedbackReceipts.get(receiptKey);
    const insight = this.inventory.find((item) => item.id === insightId);
    if (insight == null) return Object.freeze({ ok: false, error: 'insight_not_found' });
    const receipt = Object.freeze({
      ok: true,
      body: Object.freeze({
        insightId,
        action,
        accepted: true,
        recordedAt: this.now().toISOString(),
      }),
    });
    this.feedbackReceipts.set(receiptKey, receipt);
    return receipt;
  }
}

export function parseInventoryQuery(searchParams) {
  const rawCursor = searchParams.get('cursor');
  const rawLimit = searchParams.get('limit');
  const rawChannels = searchParams.get('channels');
  const cursor = rawCursor == null || rawCursor === '' ? 0 : Number(rawCursor);
  const limit = rawLimit == null || rawLimit === '' ? 36 : Number(rawLimit);
  if (!Number.isInteger(cursor) || cursor < 0 ||
      !Number.isInteger(limit) || limit < 1 || limit > 60) return null;
  const channels = rawChannels == null || rawChannels === ''
    ? null
    : new Set(rawChannels.split(',').filter(Boolean));
  if (channels != null && ([...channels].some((item) => !inventoryChannels.has(item)) ||
      channels.size !== rawChannels.split(',').length)) return null;
  return { cursor, limit, channels };
}
