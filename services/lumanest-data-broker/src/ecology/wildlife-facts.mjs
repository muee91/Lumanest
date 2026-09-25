/*
 * Regional wildlife facts: the GBIF aggregation the exploration layer shows.
 *
 * Extracted from server.mjs unchanged. Everything here is a pure transformation
 * over records that the caller already fetched, which is why the only symbol the
 * route layer needs is regionalWildlifeSummary().
 */
export const gbifBaseUrl = 'https://api.gbif.org';

const wildlifeGroups = new Map([
  ['Aves', 'bird'],
  ['Mammalia', 'mammal'],
  ['Reptilia', 'reptile'],
  ['Amphibia', 'amphibian'],
  ['Insecta', 'insect'],
]);

const wildlifeClassKeys = [
  212, // Aves
  359, // Mammalia
  358, // Reptilia
  131, // Amphibia
  216, // Insecta
];

const excludedDomesticSpecies = new Set([
  'Felis catus',
  'Canis lupus familiaris',
  'Bos taurus',
  'Equus caballus',
  'Capra hircus',
  'Ovis aries',
  'Sus scrofa domesticus',
  'Gallus gallus domesticus',
].map((name) => name.toLowerCase()));

const acceptedWildlifeBasisOfRecord = new Set([
  'HUMAN_OBSERVATION',
  'MACHINE_OBSERVATION',
  'OBSERVATION',
]);

const acceptedWildlifeLicenses = new Map([
  ['CC0_1_0', 'CC0-1.0'],
  ['http://creativecommons.org/publicdomain/zero/1.0/legalcode', 'CC0-1.0'],
  ['https://creativecommons.org/publicdomain/zero/1.0/legalcode', 'CC0-1.0'],
  ['CC_BY_4_0', 'CC-BY-4.0'],
  ['http://creativecommons.org/licenses/by/4.0/legalcode', 'CC-BY-4.0'],
  ['https://creativecommons.org/licenses/by/4.0/legalcode', 'CC-BY-4.0'],
]);

const severeWildlifeGeospatialIssues = new Set([
  'ZERO_COORDINATE',
  'COORDINATE_OUT_OF_RANGE',
  'COORDINATE_INVALID',
  'COUNTRY_COORDINATE_MISMATCH',
  'CONTINENT_COORDINATE_MISMATCH',
  'PRESUMED_SWAPPED_COORDINATE',
  'PRESUMED_NEGATED_LONGITUDE',
]);

const maximumWildlifeCoordinateUncertaintyMeters = 10_000;
const maximumWildlifeDatasetReferences = 8;
const gbifMetadataCacheTtlMilliseconds = 24 * 60 * 60 * 1_000;

function regionalWildlifeGeometry(location, radiusKm) {
  const [longitude, latitude] = location.split(',').map(Number);
  const latitudeDelta = radiusKm / 111.32;
  const longitudeDelta = radiusKm / (111.32 * Math.cos(latitude * Math.PI / 180));
  const west = longitude - longitudeDelta;
  const east = longitude + longitudeDelta;
  const south = latitude - latitudeDelta;
  const north = latitude + latitudeDelta;
  return `POLYGON((${west} ${south},${east} ${south},${east} ${north},${west} ${north},${west} ${south}))`;
}
function wildlifeGroupFor(record) {
  return wildlifeGroups.get(record.class) ?? 'other';
}
function acceptedWildlifeLicense(value) {
  return typeof value === 'string' ? acceptedWildlifeLicenses.get(value) ?? null : null;
}

function acceptedWildlifeRecord(record) {
  if (record?.coordinateUncertaintyInMeters == null) return false;
  const uncertainty = Number(record.coordinateUncertaintyInMeters);
  return record?.occurrenceStatus === 'PRESENT' &&
    acceptedWildlifeBasisOfRecord.has(record.basisOfRecord) &&
    acceptedWildlifeLicense(record.license) != null &&
    Number.isFinite(uncertainty) && uncertainty >= 0 &&
    uncertainty <= maximumWildlifeCoordinateUncertaintyMeters &&
    (!Array.isArray(record.issues) ||
      !record.issues.some((issue) => severeWildlifeGeospatialIssues.has(issue)));
}

function recordMonth(record) {
  const month = Number(record.month);
  if (Number.isInteger(month) && month >= 1 && month <= 12) return month;
  const match = typeof record.eventDate === 'string'
    ? record.eventDate.match(/^\d{4}-(\d{2})-/)
    : null;
  const parsed = Number(match?.[1]);
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 12 ? parsed : null;
}

function recordHour(record) {
  const hour = Number(record.hour);
  if (Number.isInteger(hour) && hour >= 0 && hour <= 23) return hour;
  const match = typeof record.eventDate === 'string'
    ? record.eventDate.match(/T(\d{2}):/)
    : null;
  const parsed = Number(match?.[1]);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 23 ? parsed : null;
}

function observationPeriod(hour) {
  if (hour >= 5 && hour <= 8) return 'dawn';
  if (hour >= 9 && hour <= 16) return 'day';
  if (hour >= 17 && hour <= 20) return 'dusk';
  return 'night';
}

function temporalConcentration(records) {
  const monthCounts = new Map();
  const periodCounts = new Map();
  let recordsWithMonth = 0;
  let recordsWithTime = 0;
  for (const record of records) {
    const month = recordMonth(record);
    if (month != null) {
      recordsWithMonth += 1;
      monthCounts.set(month, (monthCounts.get(month) ?? 0) + 1);
    }
    const hour = recordHour(record);
    if (hour != null) {
      recordsWithTime += 1;
      const period = observationPeriod(hour);
      periodCounts.set(period, (periodCounts.get(period) ?? 0) + 1);
    }
  }
  const byCountThenKey = (a, b) => b.records - a.records ||
    String(a.month ?? a.period).localeCompare(String(b.month ?? b.period));
  return {
    recordsWithMonth,
    recordsWithTime,
    months: [...monthCounts].map(([month, count]) => ({ month, records: count }))
      .sort(byCountThenKey),
    timePeriods: [...periodCounts].map(([period, count]) => ({ period, records: count }))
      .sort(byCountThenKey),
  };
}

function validGbifKey(value) {
  return typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function boundedGbifText(value, maximum) {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maximum &&
    !/[\u0000-\u001f\u007f]/.test(normalized)
    ? normalized
    : null;
}

function selectTraceableWildlifeRecords(records) {
  const datasetCounts = new Map();
  for (const record of records) {
    if (!validGbifKey(record.datasetKey)) continue;
    datasetCounts.set(record.datasetKey, (datasetCounts.get(record.datasetKey) ?? 0) + 1);
  }
  const selectedKeys = [...datasetCounts]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, maximumWildlifeDatasetReferences)
    .map(([key]) => key);
  const selected = new Set(selectedKeys);
  return {
    records: records.filter((record) => selected.has(record.datasetKey)),
    eligibleOccurrenceSampleSize: records.length,
    datasetsTruncated: datasetCounts.size > selected.size,
  };
}

async function gbifMetadata(path, { fetcher, cache, now, timeoutMs }) {
  const cached = cache.get(path);
  if (cached && now().getTime() - cached.createdAt < gbifMetadataCacheTtlMilliseconds) {
    return cached.value;
  }
  try {
    const upstream = await fetcher(new URL(path, gbifBaseUrl), {
      signal: AbortSignal.timeout(timeoutMs),
    });
    const value = await upstream.json();
    if (!upstream.ok || value == null || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    cache.set(path, { createdAt: now().getTime(), value });
    return value;
  } catch {
    return null;
  }
}

async function wildlifeDatasetReferences(records, dependencies) {
  const grouped = new Map();
  for (const record of records) {
    if (!validGbifKey(record.datasetKey)) continue;
    const existing = grouped.get(record.datasetKey) ?? {
      datasetKey: record.datasetKey,
      title: boundedGbifText(record.datasetTitle, 160),
      publisher: boundedGbifText(record.publishingOrgName, 160) ??
        boundedGbifText(record.institutionCode, 80),
      publishingOrgKey: validGbifKey(record.publishingOrgKey) ? record.publishingOrgKey : null,
      licenses: new Set(),
      records: 0,
    };
    existing.records += 1;
    existing.licenses.add(acceptedWildlifeLicense(record.license));
    grouped.set(record.datasetKey, existing);
  }
  const selected = [...grouped.values()]
    .sort((a, b) => b.records - a.records || a.datasetKey.localeCompare(b.datasetKey))
    .slice(0, maximumWildlifeDatasetReferences);
  return Promise.all(selected.map(async (reference) => {
    const dataset = await gbifMetadata(`/v1/dataset/${reference.datasetKey}`, dependencies);
    const organizationKey = validGbifKey(dataset?.publishingOrganizationKey)
      ? dataset.publishingOrganizationKey
      : reference.publishingOrgKey;
    const organization = organizationKey == null ? null : await gbifMetadata(
      `/v1/organization/${organizationKey}`,
      dependencies,
    );
    const title = boundedGbifText(dataset?.title, 160) ?? reference.title;
    const publisher = boundedGbifText(organization?.title, 160) ?? reference.publisher;
    const url = `https://www.gbif.org/dataset/${reference.datasetKey}`;
    const citation = boundedGbifText(dataset?.citation?.text, 500) ??
      (title == null
        ? `GBIF occurrence dataset. ${url}`
        : `${title}. ${url}`);
    return {
      datasetKey: reference.datasetKey,
      title: title ?? 'GBIF occurrence dataset',
      publisher: publisher ?? 'GBIF data publisher',
      licenses: [...reference.licenses].filter(Boolean).sort(),
      records: reference.records,
      citation,
      url,
    };
  }));
}

export async function regionalWildlifeSummary({
  location,
  radiusKm,
  fetcher,
  cache,
  now,
  cacheTtlMilliseconds,
  timeoutMs,
  metadataCache,
}) {
  const [longitude, latitude] = location.split(',').map(Number);
  const cacheKey = `${longitude.toFixed(1)},${latitude.toFixed(1)}:${radiusKm}`;
  const cached = cache.get(cacheKey);
  if (cached && now().getTime() - cached.createdAt < cacheTtlMilliseconds) {
    return cached.body;
  }
  try {
    const responses = await Promise.all(wildlifeClassKeys.map(async (classKey) => {
      const url = new URL('/v1/occurrence/search', gbifBaseUrl);
      url.searchParams.set('kingdom', 'Animalia');
      url.searchParams.set('classKey', String(classKey));
      url.searchParams.set('hasCoordinate', 'true');
      url.searchParams.set('occurrenceStatus', 'PRESENT');
      url.searchParams.set('hasGeospatialIssue', 'false');
      url.searchParams.set(
        'coordinateUncertaintyInMeters',
        String(maximumWildlifeCoordinateUncertaintyMeters),
      );
      for (const basis of acceptedWildlifeBasisOfRecord) {
        url.searchParams.append('basisOfRecord', basis);
      }
      url.searchParams.append('license', 'CC0_1_0');
      url.searchParams.append('license', 'CC_BY_4_0');
      url.searchParams.set('limit', '100');
      url.searchParams.set('geometry', regionalWildlifeGeometry(location, radiusKm));
      try {
        const upstream = await fetcher(url, { signal: AbortSignal.timeout(timeoutMs) });
        const body = await upstream.json();
        return upstream.ok && Array.isArray(body.results)
          ? { ok: true, results: body.results }
          : { ok: false, results: [] };
      } catch {
        return { ok: false, results: [] };
      }
    }));
    const successfulResponses = responses.filter((response) => response.ok);
    if (successfulResponses.length === 0) return null;
    const scannedRecords = successfulResponses.flatMap((response) => response.results);
    const qualityRecords = scannedRecords.filter(acceptedWildlifeRecord);
    const traceableCandidates = [];
    for (const record of qualityRecords) {
      const scientificName = boundedGbifText(record.species || record.scientificName, 160);
      if (scientificName == null) continue;
      if (excludedDomesticSpecies.has(scientificName.toLowerCase())) continue;
      traceableCandidates.push(record);
    }
    const selection = selectTraceableWildlifeRecords(traceableCandidates);
    const acceptedRecords = selection.records;
    const grouped = new Map();
    for (const record of acceptedRecords) {
      const scientificName = boundedGbifText(record.species || record.scientificName, 160);
      if (scientificName == null) continue;
      const existing = grouped.get(scientificName) ?? {
        scientificName,
        commonName: boundedGbifText(record.vernacularName, 120),
        animalClass: wildlifeGroupFor(record),
        records: 0,
      };
      existing.records += 1;
      grouped.set(scientificName, existing);
    }
    const taxa = [...grouped.values()]
      .sort((a, b) => b.records - a.records)
      .slice(0, 12);
    const datasets = await wildlifeDatasetReferences(acceptedRecords, {
      fetcher,
      cache: metadataCache,
      now,
      timeoutMs,
    });
    const sanitized = {
      contractVersion: 2,
      source: 'GBIF',
      scope: 'regional_wildlife_observations',
      radiusKm,
      scannedOccurrenceSampleSize: scannedRecords.length,
      eligibleOccurrenceSampleSize: selection.eligibleOccurrenceSampleSize,
      occurrenceSampleSize: acceptedRecords.length,
      datasetReferencesTruncated: selection.datasetsTruncated,
      qualityPolicy: {
        acceptedLicenses: ['CC0-1.0', 'CC-BY-4.0'],
        acceptedBasisOfRecord: [...acceptedWildlifeBasisOfRecord],
        maximumCoordinateUncertaintyMeters: maximumWildlifeCoordinateUncertaintyMeters,
        maximumDatasetReferences: maximumWildlifeDatasetReferences,
        excludesSevereGeospatialIssues: true,
      },
      historicalRecordConcentration: temporalConcentration(acceptedRecords),
      datasets,
      taxa,
    };
    cache.set(cacheKey, { createdAt: now().getTime(), body: sanitized });
    return sanitized;
  } catch {
    return null;
  }
}
