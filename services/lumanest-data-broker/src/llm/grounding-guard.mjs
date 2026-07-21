// Equipment the assistant must not invent. "相机" and "镜头" were removed
// because they are generic photography vocabulary the model naturally uses
// when answering "why is this good to shoot"; the specific gear list
// (tripod, telephoto, filter, …) is what actually needs grounding.
const equipmentTerms = [
  '三脚架', '广角镜头', '长焦镜头', '滤镜', '防雨装备', '头灯',
  '无人机', '快门线', '备用电池', '存储卡',
];

const actionTerms = [
  '出发', '前往', '导航', '进入', '等待', '立即', '务必', '最好', '建议',
  '适合去', '可以去', '值得去', '必须', '绕行', '撤离',
];

const safetyTerms = [
  '安全', '危险', '预警', '雷暴', '雷电', '封闭', '禁入', '禁止', '山洪',
  '滑坡', '泥石流', '大风', '暴雨', '风险',
];

const probabilityTerms = ['概率', '几率', '成功率', '可能性'];
const sensitiveCredentialTerms = [
  '银行卡密码', '支付密码', '登录密码', '验证码', '密钥', '私钥', '助记词',
  '身份证号', 'api key', 'access token', 'secret',
];
const hazardTerms = [
  '危险', '雷暴', '雷电', '暴雨', '大风', '山洪', '滑坡', '泥石流',
  '封闭', '禁入', '禁止',
];
const placeSuffixes = '山|峰|岭|湖|海|江|河|湾|滩|岛|街|路|巷|村|镇|城|公园|景区|湿地|草原|沙漠|峡谷|瀑布|观景台|营地|古镇|寺|桥|水库';

function parsedJson(value) {
  try {
    const parsed = JSON.parse(value);
    return parsed != null && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed
      : null;
  } catch {
    return null;
  }
}

function compact(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function tokens(value, pattern) {
  return new Set([...value.matchAll(pattern)].map((match) => match[0].replaceAll('：', ':')));
}

// Parses a matched number token (e.g. "30km", "73.9", "5.55m/s", "30公里")
// into a normalized { value, unitKey } shape. Unit aliases collapse so that
// "30公里" and "30km" compare equal, and a bare number (no unit) stays bare.
// This is what lets a model rephrase "30km" from contextFacts as "30公里"
// without the grounding guard flagging an unsupported number.
const unitAliases = new Map([
  ['km', 'km'], ['公里', 'km'],
  ['m/s', 'm/s'], ['米/秒', 'm/s'],
  ['mm', 'mm'], ['毫米', 'mm'],
  ['米', 'm'],
  ['%', '%'],
  ['分钟', 'min'], ['小时', 'h'],
  ['点', 'hour'], ['分', 'min'],
]);
const numberTokenPattern = /\d+(?:\.\d+)?(?:\s*(?:%|m\/s|mm|km|米|公里|分钟|小时|点|分))?/gu;
function parseNumberToken(raw) {
  const text = raw.trim();
  const m = text.match(/^(\d+(?:\.\d+)?)(?:\s*(%|m\/s|mm|km|米|公里|分钟|小时|点|分))?$/);
  if (!m) return null;
  const value = Number(m[1]);
  const unitKey = m[2] ? (unitAliases.get(m[2]) ?? m[2]) : 'none';
  return { value, unitKey };
}
// A number in the answer is grounded if the corpus contains the same value
// with the same (normalized) unit, or a value within a small rounding
// tolerance. Reasoning models routinely paraphrase contextFacts numbers —
// "30km" → "29km", "73.9°" → "75°" — which is an imprecise echo of the same
// authoritative figure, not a fabricated quantity. Strict equality rejected
// these and forced every answer back to the template. The tolerance is
// deliberately small: bare numbers (the riskiest, since "75" could be a
// made-up percentage) allow ±2, and unit-qualified quantities allow ±1.
// Bare numbers never satisfy a corpus number that carries a unit.
function numberIsGrounded(candidate, allowed) {
  for (const a of allowed) {
    if (a.unitKey !== candidate.unitKey) continue;
    if (a.value === candidate.value) return true;
    // Bare numbers: allow ±2 rounding (e.g. 75 vs 73.9).
    if (candidate.unitKey === 'none' && Math.abs(a.value - candidate.value) <= 2) return true;
    // Unit-qualified quantities: allow ±1 (e.g. 29km vs 30km).
    if (candidate.unitKey !== 'none' && Math.abs(a.value - candidate.value) <= 1) return true;
  }
  return false;
}
function answerNumbersGrounded(answer, corpus) {
  const allowed = [...tokens(corpus, numberTokenPattern)].map(parseNumberToken).filter(Boolean);
  for (const raw of tokens(answer, numberTokenPattern)) {
    const candidate = parseNumberToken(raw);
    if (candidate == null) continue;
    if (!numberIsGrounded(candidate, allowed)) return false;
  }
  return true;
}

function isSubset(candidate, allowed) {
  for (const value of candidate) {
    if (!allowed.has(value)) return false;
  }
  return true;
}

function unsupportedTerms(answer, template, terms) {
  return terms.filter((term) => answer.includes(term) && !template.includes(term));
}

function placeTokens(value) {
  // {1,18} so two-character place names (西湖, 黄山) — one char before the
  // suffix — are still detected as place claims. The negative lookahead
  // stops the suffix from matching when it is actually part of a common
  // non-place word: "城市风光" must not match "…城", "街景/街拍" must not
  // match "…街", "路口/路标" must not match "…路". Without this the guard
  // rejected perfectly grounded answers that merely used a word ending in
  // a place suffix character.
  const pattern = new RegExp(`[\\p{Script=Han}A-Za-z0-9·]{1,18}(?:${placeSuffixes})(?![市道路口里带子景拍边头标线])`, 'gu');
  return tokens(value, pattern);
}

function placeCore(place) {
  // Suffix-anchored two-character core of a place token, e.g. 街巷 for 看街巷.
  return [...place].slice(-2).join('');
}

function hasUnsupportedPlace(answer, template, extraNames = []) {
  const allowedPlaces = new Set([
    ...placeTokens(template),
    ...extraNames.flatMap((name) => [...placeTokens(name), name]),
  ]);
  const allowedCores = new Set([...allowedPlaces].map(placeCore));
  for (const place of placeTokens(answer)) {
    if (allowedPlaces.has(place)) continue;
    if (template.includes(place)) continue;
    // A place reference stays grounded when its suffix-anchored core already
    // appears in the bounded template (街巷 inside 看街巷), so short labels
    // rephrasing a template place are not treated as invented place claims.
    if (allowedCores.has(placeCore(place))) continue;
    return true;
  }
  return false;
}

function hasSensitiveCredentialContent(answer) {
  const normalized = answer.toLowerCase();
  return sensitiveCredentialTerms.some((term) => normalized.includes(term));
}

// A hazard word being present in the corpus does not license reversing its
// meaning. Reject positive action/quality claims tied to a hazard even when
// every individual word is otherwise grounded.
function hasDangerousSafetyReversal(answer) {
  const clauses = answer.split(/[。！？；，,]/u);
  const favorable = /适合(?:拍照|拍摄|出发|前往|进入)|值得(?:去|前往|拍)|可以(?:放心)?(?:出发|前往|进入)|无需担心|不用担心|没有危险/u;
  for (const clause of clauses) {
    if (!hazardTerms.some((term) => clause.includes(term))) continue;
    const match = favorable.exec(clause);
    if (match == null) continue;
    const prefix = clause.slice(Math.max(0, match.index - 4), match.index);
    if (/不(?:太|再)?$|并不$|不宜$|避免$|不能$|不可$/u.test(prefix)) continue;
    return true;
  }
  return false;
}

function claimSegments(value) {
  return value.split(/[。！？；，、,\n]/u).map((part) => part.trim()).filter(Boolean);
}

// Grounding individual names and numbers is insufficient: two facts from
// different source clauses must not be recombined into a new relationship.
// Whenever an answer clause binds a place to a number/time, the same binding
// must exist inside one authoritative corpus clause.
function placeNumberBindingsGrounded(answer, corpus, extraNames = []) {
  const corpusSegments = claimSegments(corpus);
  const names = new Set([
    ...placeTokens(answer),
    ...extraNames.filter((name) => typeof name === 'string' && name.length > 0 && answer.includes(name)),
  ]);
  for (const answerSegment of claimSegments(answer)) {
    const segmentPlaces = [...names].filter((name) => answerSegment.includes(name));
    const segmentNumbers = [...tokens(answerSegment, numberTokenPattern)]
      .map(parseNumberToken)
      .filter(Boolean);
    if (segmentPlaces.length === 0 || segmentNumbers.length === 0) continue;
    for (const place of segmentPlaces) {
      for (const number of segmentNumbers) {
        const supported = corpusSegments.some((segment) => {
          if (!segment.includes(place)) return false;
          const allowed = [...tokens(segment, numberTokenPattern)].map(parseNumberToken).filter(Boolean);
          return numberIsGrounded(number, allowed);
        });
        if (!supported) return false;
      }
    }
  }
  return true;
}

function guardAssistant(user, candidate) {
  const answer = compact(candidate.answer);
  const template = compact(user.templateAnswer);
  // contextFacts carries authoritative environment numbers/labels (weather,
  // sun/moon, sky opportunity, wildlife) assembled by the Broker. searchResults
  // carries excerpts from the Tavily web_search tool, already filtered through
  // the reviewed sourcePolicies allow-list. Answers may reference facts from
  // any of these, so the allowed corpus is the union of all three. Place names
  // are similarly admitted from the corpus: source authority is enforced
  // upstream by sourcePolicies, so a place mentioned in a whitelisted excerpt
  // is acceptable to echo. URLs are still forbidden in the answer itself.
  const contextFacts = compact(typeof user.contextFacts === 'string' ? user.contextFacts : '');
  const searchResults = compact(typeof user.searchResults === 'string' ? user.searchResults : '');
  const corpusParts = [template];
  if (contextFacts.length > 0) corpusParts.push(contextFacts);
  if (searchResults.length > 0) corpusParts.push(searchResults);
  const corpus = corpusParts.join(' ');
  if (!answer || [...answer].length > 80 || /[\r\n]/.test(answer) || /https?:\/\//i.test(answer)) {
    return { ok: false, reason: 'invalid_shape' };
  }

  if (hasSensitiveCredentialContent(answer)) {
    return { ok: false, reason: 'sensitive_credential' };
  }
  if (hasDangerousSafetyReversal(answer)) {
    return { ok: false, reason: 'safety_polarity_reversal' };
  }

  if (!answerNumbersGrounded(answer, corpus)) return { ok: false, reason: 'unsupported_number' };

  const answerTimes = tokens(answer, /\b\d{1,2}[：:]\d{2}\b/gu);
  const allowedTimes = tokens(corpus, /\b\d{1,2}[：:]\d{2}\b/gu);
  if (!isSubset(answerTimes, allowedTimes)) return { ok: false, reason: 'unsupported_time' };

  if (unsupportedTerms(answer, corpus, equipmentTerms).length > 0) {
    return { ok: false, reason: 'unsupported_equipment' };
  }
  if (unsupportedTerms(answer, corpus, actionTerms).length > 0) {
    return { ok: false, reason: 'unsupported_action' };
  }
  if (unsupportedTerms(answer, corpus, safetyTerms).length > 0) {
    return { ok: false, reason: 'unsupported_safety_claim' };
  }
  if (unsupportedTerms(answer, corpus, probabilityTerms).length > 0 || /\d+(?:\.\d+)?\s*%/.test(answer)) {
    return { ok: false, reason: 'unsupported_probability' };
  }

  const extraNames = Array.isArray(user.placeSummaries)
    ? user.placeSummaries.flatMap((place) => typeof place?.name === 'string' ? [place.name.trim()] : [])
    : [];
  if (hasUnsupportedPlace(answer, corpus, extraNames)) {
    return { ok: false, reason: 'unsupported_place' };
  }
  if (!placeNumberBindingsGrounded(answer, corpus, extraNames)) {
    return { ok: false, reason: 'unsupported_fact_binding' };
  }

  return { ok: true };
}

function guardNarrative(user, candidate) {
  const summary = compact(candidate.summary);
  const template = compact(user.templateSummary);
  if (!summary || [...summary].length > 80 || /[\r\n]/.test(summary) || /https?:\/\//i.test(summary)) {
    return { ok: false, reason: 'invalid_shape' };
  }
  const answerNumbers = tokens(summary, /\d+(?:\.\d+)?(?:\s*(?:%|m\/s|mm|km|米|公里|分钟|小时|点|分))?/gu);
  const allowedNumbers = tokens(template, /\d+(?:\.\d+)?(?:\s*(?:%|m\/s|mm|km|米|公里|分钟|小时|点|分))?/gu);
  if (!isSubset(answerNumbers, allowedNumbers)) return { ok: false, reason: 'unsupported_number' };
  if (unsupportedTerms(summary, template, equipmentTerms).length > 0) {
    return { ok: false, reason: 'unsupported_equipment' };
  }
  if (unsupportedTerms(summary, template, safetyTerms).length > 0) {
    return { ok: false, reason: 'unsupported_safety_claim' };
  }
  if (unsupportedTerms(summary, template, actionTerms).length > 0) {
    return { ok: false, reason: 'unsupported_action' };
  }
  if (unsupportedTerms(summary, template, probabilityTerms).length > 0 || /\d+(?:\.\d+)?\s*%/.test(summary)) {
    return { ok: false, reason: 'unsupported_probability' };
  }
  if (hasUnsupportedPlace(summary, template)) {
    return { ok: false, reason: 'unsupported_place' };
  }

  if (candidate.noteLabels == null || typeof candidate.noteLabels !== 'object' || Array.isArray(candidate.noteLabels)) {
    return { ok: false, reason: 'invalid_labels' };
  }
  const allowedIds = new Set(Array.isArray(user.allowedCreativeEventIds) ? user.allowedCreativeEventIds : []);
  for (const [id, labelValue] of Object.entries(candidate.noteLabels)) {
    const label = compact(labelValue);
    if (!allowedIds.has(id) || [...label].length < 2 || [...label].length > 8 || /\d|https?:\/\//i.test(label)) {
      return { ok: false, reason: 'invalid_labels' };
    }
    if (unsupportedTerms(label, template, equipmentTerms).length > 0 ||
        unsupportedTerms(label, template, safetyTerms).length > 0 ||
        unsupportedTerms(label, template, actionTerms).length > 0 ||
        hasUnsupportedPlace(label, template)) {
      return { ok: false, reason: 'unsupported_label_claim' };
    }
  }
  return { ok: true };
}

function guardGeneralAssistant(user, candidate) {
  const answer = compact(candidate.answer);
  const searchResults = compact(
    typeof user.searchResults === 'string' ? user.searchResults : '',
  );
  if (!answer || [...answer].length > 200 || /[\r\n]/.test(answer) || /https?:\/\//i.test(answer)) {
    return { ok: false, reason: 'invalid_shape' };
  }
  if (hasSensitiveCredentialContent(answer)) {
    return { ok: false, reason: 'sensitive_credential' };
  }
  const safetyCheckedAnswer = answer.replaceAll('安全快门', '');
  if (hasDangerousSafetyReversal(safetyCheckedAnswer) ||
      safetyTerms.some((term) => safetyCheckedAnswer.includes(term))) {
    return { ok: false, reason: 'unsupported_safety_claim' };
  }
  const liveClaim = /(?:当前|现在|今晚|明天|此刻).{0,16}(?:天气|气温|风|云|日出|日落|开放|封闭|适合去|可以去|值得去)/u;
  if (liveClaim.test(answer) && searchResults.length === 0) {
    return { ok: false, reason: 'unsupported_live_claim' };
  }
  if (hasUnsupportedPlace(answer, searchResults)) {
    return { ok: false, reason: 'unsupported_place' };
  }
  if (searchResults.length > 0 &&
      !placeNumberBindingsGrounded(answer, searchResults)) {
    return { ok: false, reason: 'unsupported_fact_binding' };
  }
  return { ok: true };
}

export function guardGroundedOutput({ prompt, text }) {
  const user = parsedJson(prompt?.user);
  if (user?.responseMode === 'general') {
    const candidate = parsedJson(text);
    if (candidate == null) {
      return { ok: false, error: 'invalid_response', reason: 'invalid_json' };
    }
    const guarded = guardGeneralAssistant(user, candidate);
    return guarded.ok
      ? { ok: true, text }
      : { ok: false, error: 'invalid_response', reason: guarded.reason };
  }
  if (user == null || (typeof user.templateAnswer !== 'string' && typeof user.templateSummary !== 'string')) {
    return { ok: true, text };
  }
  const candidate = parsedJson(text);
  if (candidate == null) {
    return { ok: false, error: 'invalid_response', reason: 'invalid_json' };
  }

  const guarded = typeof user.templateAnswer === 'string'
    ? guardAssistant(user, candidate)
    : guardNarrative(user, candidate);

  return guarded.ok
    ? { ok: true, text }
    : { ok: false, error: 'invalid_response', reason: guarded.reason };
}
