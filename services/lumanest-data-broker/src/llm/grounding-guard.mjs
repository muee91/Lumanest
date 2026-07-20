const equipmentTerms = [
  '三脚架', '广角镜头', '长焦镜头', '滤镜', '防雨装备', '头灯',
  '相机', '镜头', '无人机', '快门线', '备用电池', '存储卡',
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
  const pattern = new RegExp(`[\\p{Script=Han}A-Za-z0-9·]{2,18}(?:${placeSuffixes})`, 'gu');
  return tokens(value, pattern);
}

function guardAssistant(user, candidate) {
  const answer = compact(candidate.answer);
  const template = compact(user.templateAnswer);
  if (!answer || [...answer].length > 80 || /[\r\n]/.test(answer) || /https?:\/\//i.test(answer)) {
    return { ok: false, reason: 'invalid_shape' };
  }

  const answerNumbers = tokens(answer, /\d+(?:\.\d+)?(?:\s*(?:%|m\/s|mm|km|米|公里|分钟|小时|点|分))?/gu);
  const allowedNumbers = tokens(template, /\d+(?:\.\d+)?(?:\s*(?:%|m\/s|mm|km|米|公里|分钟|小时|点|分))?/gu);
  if (!isSubset(answerNumbers, allowedNumbers)) return { ok: false, reason: 'unsupported_number' };

  const answerTimes = tokens(answer, /\b\d{1,2}[：:]\d{2}\b/gu);
  const allowedTimes = tokens(template, /\b\d{1,2}[：:]\d{2}\b/gu);
  if (!isSubset(answerTimes, allowedTimes)) return { ok: false, reason: 'unsupported_time' };

  if (unsupportedTerms(answer, template, equipmentTerms).length > 0) {
    return { ok: false, reason: 'unsupported_equipment' };
  }
  if (unsupportedTerms(answer, template, actionTerms).length > 0) {
    return { ok: false, reason: 'unsupported_action' };
  }
  if (unsupportedTerms(answer, template, safetyTerms).length > 0) {
    return { ok: false, reason: 'unsupported_safety_claim' };
  }
  if (unsupportedTerms(answer, template, probabilityTerms).length > 0 || /\d+(?:\.\d+)?\s*%/.test(answer)) {
    return { ok: false, reason: 'unsupported_probability' };
  }

  const allowedPlaces = new Set([
    ...placeTokens(template),
    ...(Array.isArray(user.placeSummaries)
      ? user.placeSummaries.flatMap((place) => typeof place?.name === 'string' ? [...placeTokens(place.name), place.name.trim()] : [])
      : []),
  ]);
  for (const place of placeTokens(answer)) {
    if (!allowedPlaces.has(place) && !template.includes(place)) {
      return { ok: false, reason: 'unsupported_place' };
    }
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
  if (unsupportedTerms(summary, template, safetyTerms).length > 0) {
    return { ok: false, reason: 'unsupported_safety_claim' };
  }
  if (unsupportedTerms(summary, template, actionTerms).length > 0) {
    return { ok: false, reason: 'unsupported_action' };
  }
  if (unsupportedTerms(summary, template, probabilityTerms).length > 0 || /\d+(?:\.\d+)?\s*%/.test(summary)) {
    return { ok: false, reason: 'unsupported_probability' };
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
    if (unsupportedTerms(label, template, safetyTerms).length > 0 || unsupportedTerms(label, template, actionTerms).length > 0) {
      return { ok: false, reason: 'unsupported_label_claim' };
    }
  }
  return { ok: true };
}

export function guardGroundedOutput({ prompt, text }) {
  const user = parsedJson(prompt?.user);
  const candidate = parsedJson(text);
  if (user == null || candidate == null) {
    return { ok: false, error: 'invalid_response', reason: 'invalid_json' };
  }

  const guarded = typeof user.templateAnswer === 'string'
    ? guardAssistant(user, candidate)
    : typeof user.templateSummary === 'string'
      ? guardNarrative(user, candidate)
      : { ok: true };

  return guarded.ok
    ? { ok: true, text }
    : { ok: false, error: 'invalid_response', reason: guarded.reason };
}
