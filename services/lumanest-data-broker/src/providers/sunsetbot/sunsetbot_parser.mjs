const numericPattern = /[-+]?[0-9]*\.?[0-9]+/;
const maximumQualityScore = 5;
const maximumAod = 5;
const providerStatuses = new Set([
  'ok', 'not_found', 'invalid', 'rate_limited', 'timeout', 'upstream_error',
  'parse_error', 'circuit_open', 'unknown',
]);

function decodeEntities(value) {
  return value.replace(/&(#x?[0-9a-f]+|nbsp|ensp|emsp|amp|lt|gt|quot|apos);/gi, (match, entity) => {
    const normalized = entity.toLowerCase();
    if (['nbsp', 'ensp', 'emsp'].includes(normalized)) return ' ';
    if (normalized === 'amp') return '&';
    if (normalized === 'lt') return '<';
    if (normalized === 'gt') return '>';
    if (normalized === 'quot') return '"';
    if (normalized === 'apos') return "'";
    const hexadecimal = normalized.startsWith('#x');
    const digits = normalized.slice(hexadecimal ? 2 : 1);
    const codePoint = Number.parseInt(digits, hexadecimal ? 16 : 10);
    if (!Number.isInteger(codePoint) || codePoint < 0 || codePoint > 0x10ffff) return match;
    return String.fromCodePoint(codePoint);
  });
}

export function cleanSunsetBotHtml(value) {
  if (value == null) return '';
  return decodeEntities(String(value)
    .replace(/<br\s*\/?\s*>/gi, ' ')
    .replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

export function parseProviderNumeric(value) {
  const cleaned = cleanSunsetBotHtml(value);
  const match = numericPattern.exec(cleaned);
  if (match == null) {
    return { value: null, providerLabel: cleaned || null, valid: false };
  }
  const parsed = Number.parseFloat(match[0]);
  const remainder = `${cleaned.slice(0, match.index)} ${cleaned.slice(match.index + match[0].length)}`
    .replace(/^[\s:：,，;；(（\[【]+|[\s)）\]】]+$/g, '')
    .trim();
  return {
    value: Number.isFinite(parsed) ? parsed : null,
    providerLabel: remainder || null,
    valid: Number.isFinite(parsed),
  };
}

export function parseProviderEventTime(value) {
  const raw = cleanSunsetBotHtml(value);
  const match = /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/.exec(raw);
  if (match == null) return { eventTime: null, rawEventTime: raw || null };
  const parts = match.slice(1).map(Number);
  const [year, month, day, hour, minute, second] = parts;
  const utc = new Date(Date.UTC(year, month - 1, day, hour - 8, minute, second));
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  });
  const values = Object.fromEntries(formatter.formatToParts(utc)
    .filter((part) => part.type !== 'literal')
    .map((part) => [part.type, Number(part.value)]));
  if (values.year !== year || values.month !== month || values.day !== day ||
      values.hour !== hour || values.minute !== minute || values.second !== second) {
    return { eventTime: null, rawEventTime: raw };
  }
  return {
    eventTime: `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}+08:00`,
    rawEventTime: raw,
  };
}

function normalizedStatus(value) {
  const status = String(value ?? '').trim().toLowerCase();
  if (status === 'ok') return 'ok';
  if (['not_found', 'notfound', 'city_not_found'].includes(status)) return 'not_found';
  if (['invalid', 'bad_request'].includes(status)) return 'invalid';
  if (['rate_limited', 'too_many_requests'].includes(status)) return 'rate_limited';
  return providerStatuses.has(status) ? status : 'unknown';
}

export function parseSunsetBotResponse(body, { model }) {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return { model, status: 'parse_error', parseStatus: 'invalid_body' };
  }
  const status = normalizedStatus(body.status);
  if (status !== 'ok') {
    return {
      model,
      status,
      parseStatus: 'provider_status',
      rawResponseSummary: cleanSunsetBotHtml(body.place_holder ?? body.img_summary).slice(0, 240),
    };
  }
  const quality = parseProviderNumeric(body.tb_quality);
  const aod = parseProviderNumeric(body.tb_aod);
  const time = parseProviderEventTime(body.tb_event_time);
  const qualityValid = quality.valid && quality.value >= 0 && quality.value <= maximumQualityScore;
  const aodValid = aod.valid && aod.value >= 0 && aod.value <= maximumAod;
  let parseStatus = 'ok';
  if (!qualityValid && cleanSunsetBotHtml(body.tb_quality)) parseStatus = 'invalid_numeric_field';
  else if (!qualityValid || !aodValid || time.eventTime == null) parseStatus = 'partial';
  return {
    model,
    status: 'ok',
    parseStatus,
    score: qualityValid ? quality.value : null,
    providerLabel: quality.providerLabel,
    aod: aodValid ? aod.value : null,
    aodLabel: aod.providerLabel,
    eventTime: time.eventTime,
    rawEventTime: time.eventTime == null ? time.rawEventTime : null,
    providerLocalTimeZone: 'Asia/Shanghai',
  };
}
