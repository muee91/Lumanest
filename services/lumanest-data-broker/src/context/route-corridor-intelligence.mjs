const facilityKeys = Object.freeze([
  'parking', 'fuel', 'food', 'water', 'toilets', 'shelter', 'restArea',
]);
const restrictionKinds = new Set([
  'closure', 'roadClosure', 'fireRestriction', 'regulation', 'eventChange',
]);

function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function count(value) {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 1_000
    ? value : 0;
}

function responsive(provider) {
  return provider != null && ['ready', 'noData'].includes(provider.status);
}

function source(provider) {
  const value = provider?.source;
  if (!object(value) || typeof value.id !== 'string' || typeof value.title !== 'string' ||
      typeof value.publisher !== 'string' || typeof value.url !== 'string') return null;
  return {
    id: value.id,
    title: value.title,
    publisher: value.publisher,
    url: value.url,
    license: typeof value.license === 'string' ? value.license : null,
    version: typeof value.version === 'string' ? value.version : null,
  };
}

export function buildRouteCorridorIntelligence({ body, providerResults, generatedAt }) {
  const bundles = Array.isArray(providerResults) ? providerResults : [];
  const segments = [];
  const sourceMap = new Map();
  let availableSegments = 0;

  for (let index = 0; index < body.samples.length; index += 1) {
    const sample = body.samples[index];
    const bundle = object(bundles[index]) ? bundles[index] : null;
    const providers = Array.isArray(bundle?.providers) ? bundle.providers : [];
    const osm = providers.find((item) => item?.id === 'osm');
    const official = providers.find((item) => item?.id === 'officialNotices');
    for (const provider of [osm, official]) {
      const item = source(provider);
      if (item != null && responsive(provider)) sourceMap.set(item.id, item);
    }

    const mapSignal = osm?.status === 'ready'
      ? osm.signals?.find((item) => item?.kind === 'outdoorMapInventory' && item.verification === 'reference')
      : null;
    const attributes = object(mapSignal?.attributes) ? mapSignal.attributes : {};
    const facilities = Object.fromEntries(facilityKeys.map((key) => [key, count(attributes[key])]));
    const mapResponsive = responsive(osm);
    const officialResponsive = responsive(official);
    if (mapResponsive || officialResponsive) availableSegments += 1;

    const restrictions = official?.status === 'ready'
      ? (official.signals ?? []).filter((item) =>
          item?.verification === 'authoritative' && restrictionKinds.has(item.kind))
      : [];
    const restrictionFactIds = restrictions
      .map((item) => typeof item.id === 'string' ? item.id : null)
      .filter(Boolean)
      .slice(0, 4);
    const evidenceFactIds = [
      ...(typeof mapSignal?.id === 'string' ? [mapSignal.id] : []),
      ...restrictionFactIds,
    ].slice(0, 5);
    segments.push({
      progress: Number(sample.progress.toFixed(4)),
      expectedAt: new Date(sample.expectedAt).toISOString(),
      facilities: {
        status: mapSignal != null ? 'reference' : mapResponsive ? 'empty' : 'unavailable',
        ...facilities,
      },
      photography: {
        status: mapSignal == null ? (mapResponsive ? 'noReference' : 'unavailable')
          : count(attributes.viewpoint) + count(attributes.historic) > 0 ? 'reference' : 'noReference',
        viewpointCount: count(attributes.viewpoint),
        heritageCount: count(attributes.historic),
      },
      restrictions: {
        status: restrictions.length > 0 ? 'present' : officialResponsive ? 'noneObserved' : 'unavailable',
        kinds: [...new Set(restrictions.map((item) => item.kind))].slice(0, 4),
        authoritative: restrictions.length > 0,
        factIds: restrictionFactIds,
      },
      evidence: {
        status: restrictions.length > 0 ? 'verified' : mapSignal != null ? 'reference' : 'unavailable',
        factIds: evidenceFactIds,
      },
    });
  }

  return {
    contractVersion: 1,
    generatedAt: generatedAt.toISOString(),
    coverage: availableSegments === 0 ? 'unavailable'
      : availableSegments === body.samples.length ? 'full' : 'partial',
    requestedSegments: body.samples.length,
    availableSegments,
    sources: [...sourceMap.values()].slice(0, 4),
    segments,
    limitations: [
      'public_map_inventory_is_reference_only',
      'absence_of_official_notice_is_not_safety_confirmation',
      'precise_route_geometry_excluded',
    ],
  };
}
