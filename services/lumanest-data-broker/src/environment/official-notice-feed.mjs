const maximumFeedBytes = 512 * 1024;
const safetyKinds = new Set(['closure', 'roadClosure', 'fireRestriction', 'regulation']);

function boundedText(value, maximum = 360) {
  if (typeof value !== 'string') return null;
  const normalized = value
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;|&#34;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, code) => {
      const value = Number(code);
      return Number.isInteger(value) && value > 0 && value <= 0x10ffff
        ? String.fromCodePoint(value)
        : ' ';
    })
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return normalized.length > 0 ? [...normalized].slice(0, maximum).join('') : null;
}

function httpsUrl(value, fallback = null) {
  if (typeof value !== 'string' || value.length > 2_048) return fallback;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password ? url.toString() : fallback;
  } catch {
    return fallback;
  }
}

function iso(value) {
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed.toISOString() : null;
}

function xmlValue(block, tag) {
  const expression = new RegExp(
    `<(?:[A-Za-z0-9_-]+:)?${tag}\\b[^>]*>([\\s\\S]*?)<\\/(?:[A-Za-z0-9_-]+:)?${tag}>`,
    'i',
  );
  return expression.exec(block)?.[1] ?? null;
}

function xmlLink(block, fallback) {
  const href = /<(?:[A-Za-z0-9_-]+:)?link\b[^>]*href=["']([^"']+)["'][^>]*>/i.exec(block)?.[1];
  return httpsUrl(href, httpsUrl(boundedText(xmlValue(block, 'link'), 2_048), fallback));
}

function parseXmlFeed(text, fallbackUrl) {
  const blocks = [
    ...text.matchAll(/<(?:[A-Za-z0-9_-]+:)?item\b[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?item>/gi),
    ...text.matchAll(/<(?:[A-Za-z0-9_-]+:)?entry\b[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?entry>/gi),
  ].map((match) => match[1]);
  return blocks.slice(0, 40).flatMap((block) => {
    const title = boundedText(xmlValue(block, 'title'), 160);
    const summary = boundedText(
      xmlValue(block, 'description') ?? xmlValue(block, 'summary') ?? xmlValue(block, 'content'),
      1_200,
    );
    const publishedAt = iso(
      boundedText(
        xmlValue(block, 'pubDate') ?? xmlValue(block, 'published') ?? xmlValue(block, 'updated'),
        120,
      ),
    );
    if (!title || !publishedAt) return [];
    return [{
      title,
      summary: summary ?? title,
      url: xmlLink(block, fallbackUrl),
      publishedAt,
    }];
  });
}

function parseJsonFeed(text, fallbackUrl) {
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return [];
  }
  const entries = Array.isArray(body?.items)
    ? body.items
    : Array.isArray(body?.entries)
      ? body.entries
      : Array.isArray(body)
        ? body
        : [];
  return entries.slice(0, 40).flatMap((item) => {
    const title = boundedText(item?.title ?? item?.name, 160);
    const summary = boundedText(
      item?.summary ?? item?.content_text ?? item?.content_html ?? item?.description ?? item?.content,
      1_200,
    );
    const publishedAt = iso(
      item?.date_published ?? item?.date_modified ?? item?.publishedAt ?? item?.published ?? item?.updated,
    );
    if (!title || !publishedAt) return [];
    return [{
      title,
      summary: summary ?? title,
      url: httpsUrl(item?.url ?? item?.external_url ?? item?.link, fallbackUrl),
      publishedAt,
    }];
  });
}

function classify(text) {
  if (/恢复开放|恢复营业|重新开放|reopen(?:ed|ing)?/i.test(text)) return 'reopening';
  if (/封路|道路封闭|交通管制|道路中断|公路中断|road\s+(?:is\s+)?closed|road closure/i.test(text)) {
    return 'roadClosure';
  }
  if (/森林防火|防火封闭|禁火|高火险|fire\s+(?:ban|restriction)|wildfire restriction/i.test(text)) {
    return 'fireRestriction';
  }
  if (/闭园|闭馆|关闭|暂停开放|临时封闭|停止接待|停止开放|temporarily closed|closure/i.test(text)) {
    return 'closure';
  }
  if (/禁止进入|禁止通行|限制进入|限流|管制|预约进入|restriction|prohibited|access limited/i.test(text)) {
    return 'regulation';
  }
  if (/取消|延期|改期|暂停举办|cancelled|canceled|postponed|rescheduled/i.test(text)) {
    return 'eventChange';
  }
  return null;
}

function explicitExpiry(text, publishedAt) {
  const candidates = [];
  for (const match of text.matchAll(/(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})日?(?:\s*[T ]?\s*(\d{1,2})(?:[:时](\d{1,2}))?分?)?/g)) {
    const value = Date.UTC(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
      Number(match[4] ?? 23),
      Number(match[5] ?? 59),
    );
    if (Number.isFinite(value) && value > Date.parse(publishedAt)) candidates.push(value);
  }
  for (const match of text.matchAll(/(?:至|截至|有效期至|until|through)\s*(\d{1,2})[-/.月](\d{1,2})日?(?:\s*(\d{1,2})(?:[:时](\d{1,2}))?分?)?/gi)) {
    const published = new Date(publishedAt);
    let year = published.getUTCFullYear();
    const month = Number(match[1]);
    const day = Number(match[2]);
    let value = Date.UTC(year, month - 1, day, Number(match[3] ?? 23), Number(match[4] ?? 59));
    if (value <= published.getTime()) value = Date.UTC(year + 1, month - 1, day, Number(match[3] ?? 23), Number(match[4] ?? 59));
    if (Number.isFinite(value)) candidates.push(value);
  }
  return candidates.length === 0 ? null : new Date(Math.max(...candidates)).toISOString();
}

function distanceKm(aLat, aLon, bLat, bLon) {
  const radians = (value) => value * Math.PI / 180;
  const dLat = radians(bLat - aLat);
  const dLon = radians(bLon - aLon);
  const latitude = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(aLat)) * Math.cos(radians(bLat)) * Math.sin(dLon / 2) ** 2;
  return 6_371 * 2 * Math.atan2(Math.sqrt(latitude), Math.sqrt(1 - latitude));
}

function covers(source, query) {
  return distanceKm(
    source.coverage.latitude,
    source.coverage.longitude,
    query.latitude,
    query.longitude,
  ) <= source.coverage.radiusKm + query.radiusKm;
}

async function boundedFeed(fetcher, source, timeoutMs) {
  const response = await fetcher(source.feedUrl, {
    redirect: 'error',
    signal: AbortSignal.timeout(timeoutMs),
    headers: {
      Accept: source.format === 'jsonFeed'
        ? 'application/feed+json, application/json;q=0.9, text/plain;q=0.5'
        : 'application/atom+xml, application/rss+xml, application/xml;q=0.9, text/xml;q=0.8',
      'User-Agent': 'LumaNest/1.0 OfficialNoticeReader',
    },
  });
  const declared = Number.parseInt(response.headers.get('content-length') ?? '', 10);
  if (!response.ok || (Number.isFinite(declared) && declared > maximumFeedBytes)) {
    throw new Error(response.ok ? 'feed_too_large' : `http_${response.status}`);
  }
  const text = await response.text();
  if (Buffer.byteLength(text, 'utf8') > maximumFeedBytes) throw new Error('feed_too_large');
  return text;
}

function normalizeEntry(source, entry, now) {
  const combined = `${entry.title} ${entry.summary}`;
  const kind = classify(combined);
  if (kind == null || !source.allowedKinds.includes(kind)) return null;
  const observedAt = iso(entry.publishedAt);
  if (!observedAt || Date.parse(observedAt) > now.getTime() + 10 * 60 * 1_000) return null;
  const explicit = explicitExpiry(combined, observedAt);
  const expiresAt = explicit ?? new Date(
    Date.parse(observedAt) + source.defaultExpiryMinutes * 60 * 1_000,
  ).toISOString();
  if (Date.parse(expiresAt) <= now.getTime()) return null;
  const safetyEligible = source.enabled && source.authoritative && source.promoteToSafety &&
    safetyKinds.has(kind) && (explicit != null || source.allowDefaultSafetyExpiry);
  const severity = kind === 'fireRestriction' || kind === 'roadClosure'
    ? 'warning'
    : kind === 'closure'
      ? 'warning'
      : 'caution';
  return {
    kind,
    title: entry.title,
    summary: entry.summary,
    observedAt,
    expiresAt,
    sourceUrl: entry.url ?? source.homepageUrl,
    sourceId: source.id,
    sourceName: source.name,
    sourceHomepageUrl: source.homepageUrl,
    authoritative: source.authoritative,
    safetyEligible,
    severity,
    expiryExplicit: explicit != null,
  };
}

export async function loadOfficialNoticeItems({ sources, query, fetcher = fetch, timeoutMs = 8_000, now = new Date() }) {
  const selected = sources.filter((source) => source.enabled && covers(source, query));
  const results = await Promise.all(selected.map(async (source) => {
    try {
      const text = await boundedFeed(fetcher, source, timeoutMs);
      const entries = source.format === 'jsonFeed'
        ? parseJsonFeed(text, source.homepageUrl)
        : parseXmlFeed(text, source.homepageUrl);
      return {
        source,
        status: 'ready',
        items: entries.map((entry) => normalizeEntry(source, entry, now)).filter(Boolean),
      };
    } catch (error) {
      return {
        source,
        status: 'unavailable',
        error: typeof error?.message === 'string' ? error.message : 'upstream_unavailable',
        items: [],
      };
    }
  }));
  const items = results
    .flatMap((result) => result.items)
    .sort((a, b) => {
      if (a.safetyEligible !== b.safetyEligible) return a.safetyEligible ? -1 : 1;
      return Date.parse(b.observedAt) - Date.parse(a.observedAt);
    })
    .slice(0, 8);
  return {
    items,
    checkedSources: results.length,
    unavailableSources: results.filter((result) => result.status === 'unavailable').length,
  };
}

export const officialNoticeSafetyKinds = safetyKinds;
