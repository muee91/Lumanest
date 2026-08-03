import assert from 'node:assert/strict';
import test from 'node:test';

import { guardGroundedOutput } from '../src/llm/grounding-guard.mjs';

function assistantPrompt(templateAnswer, placeSummaries = [], contextFacts = '', searchResults = '') {
  return {
    system: 'bounded assistant',
    user: JSON.stringify({
      questionType: 'nearby',
      templateAnswer,
      placeSummaries,
      contextFacts,
      searchResults,
      tone: 'balanced',
    }),
  };
}

function narrativePrompt(templateSummary = '云层正在打开，继续观察。') {
  return {
    system: 'bounded narrative',
    user: JSON.stringify({
      templateSummary,
      allowedCreativeEventIds: ['event.one'],
    }),
  };
}

function generalPrompt(question, contextFacts = '', searchResults = '') {
  return {
    system: 'general photography assistant',
    user: JSON.stringify({
      responseMode: 'general', question, tone: 'balanced', contextFacts, searchResults,
    }),
  };
}

test('general assistant answers photography questions without a template', () => {
  const accepted = guardGroundedOutput({
    prompt: generalPrompt('直方图怎么用？'),
    text: JSON.stringify({
      answer: '直方图反映亮度分布：左侧是暗部，右侧是高光。拍摄时主要用它检查高光是否溢出。',
    }),
  });
  assert.equal(accepted.ok, true);
  const safeShutter = guardGroundedOutput({
    prompt: generalPrompt('安全快门是什么？'),
    text: JSON.stringify({ answer: '安全快门是手持拍摄时，较不容易因手抖产生模糊的快门速度参考。' }),
  });
  assert.equal(safeShutter.ok, true);
  const inventedLiveFact = guardGroundedOutput({
    prompt: generalPrompt('现在拍什么？'),
    text: JSON.stringify({ answer: '现在云层很薄，今晚日落值得去拍。' }),
  });
  assert.equal(inventedLiveFact.ok, false);
  assert.equal(inventedLiveFact.reason, 'unsupported_live_claim');
});

test('accepts a natural rewrite that keeps the same facts', () => {
  const result = guardGroundedOutput({
    prompt: assistantPrompt('当前窗口是18:20—18:45，先看时间再决定是否出发。'),
    text: JSON.stringify({ answer: '窗口仍是18:20—18:45，先确认时间再决定是否出发。' }),
  });
  assert.equal(result.ok, true);
});

test('rejects a new time, probability and action claim', () => {
  const newTime = guardGroundedOutput({
    prompt: assistantPrompt('当前窗口是18:20—18:45，先看时间再决定是否出发。'),
    text: JSON.stringify({ answer: '19:30出发最合适。' }),
  });
  assert.equal(newTime.ok, false);
  assert.equal(newTime.reason, 'unsupported_number');

  const probability = guardGroundedOutput({
    prompt: assistantPrompt('当前条件仍需观察。'),
    text: JSON.stringify({ answer: '成功率有80%。' }),
  });
  assert.equal(probability.ok, false);

  const action = guardGroundedOutput({
    prompt: assistantPrompt('当前条件仍需观察。'),
    text: JSON.stringify({ answer: '建议立即前往。' }),
  });
  assert.equal(action.ok, false);
  assert.equal(action.reason, 'unsupported_action');
});

test('rejects an ungrounded place or equipment item', () => {
  const place = guardGroundedOutput({
    prompt: assistantPrompt('当前附近可以先看西湖。', [{ name: '西湖' }]),
    text: JSON.stringify({ answer: '北山街是最佳选择。' }),
  });
  assert.equal(place.ok, false);
  assert.equal(place.reason, 'unsupported_place');

  const equipment = guardGroundedOutput({
    prompt: assistantPrompt('当前没有额外器材要求。'),
    text: JSON.stringify({ answer: '最好带无人机。' }),
  });
  assert.equal(equipment.ok, false);
  assert.equal(equipment.reason, 'unsupported_equipment');
});

test('narrative labels remain tied to allowed creative ids', () => {
  const prompt = narrativePrompt();
  const accepted = guardGroundedOutput({
    prompt,
    text: JSON.stringify({ summary: '云层正在打开，可以继续观察。', noteLabels: { 'event.one': '云开' } }),
  });
  assert.equal(accepted.ok, true);

  const rejected = guardGroundedOutput({
    prompt,
    text: JSON.stringify({ summary: '云层正在打开。', noteLabels: { 'event.two': '立刻出发' } }),
  });
  assert.equal(rejected.ok, false);
});

test('narrative cannot invent a place or equipment recommendation', () => {
  const inventedPlace = guardGroundedOutput({
    prompt: narrativePrompt(),
    text: JSON.stringify({
      summary: '西湖云层正在打开。',
      noteLabels: { 'event.one': '云开' },
    }),
  });
  assert.equal(inventedPlace.ok, false);
  assert.equal(inventedPlace.reason, 'unsupported_place');

  const inventedEquipment = guardGroundedOutput({
    prompt: narrativePrompt(),
    text: JSON.stringify({
      summary: '云层正在打开，带上三脚架。',
      noteLabels: { 'event.one': '云开' },
    }),
  });
  assert.equal(inventedEquipment.ok, false);
  assert.equal(inventedEquipment.reason, 'unsupported_equipment');
});

test('assistant may cite facts that come from the contextFacts card', () => {
  const facts = '天气：cloudy、26°C、风1.8m/s、云量55；日月：sunset、太阳高度4°；今晚日落光色：值得留意、置信高、日落18:32';
  // Temperature, wind speed, cloud cover and the sunset time all live only in
  // contextFacts — the template carries none of them — so the guard must treat
  // the fact card as an allowed corpus and accept the rewrite. Note the card
  // avoids the “%” glyph because the guard rejects any “<number>%” as a
  // probability claim; cloud cover is a bare number instead.
  const accepted = guardGroundedOutput({
    prompt: assistantPrompt('先看当前窗口，再决定下一步。', [], facts),
    text: JSON.stringify({ answer: '现在26°C、云量55，今晚日落18:32光色值得留意。' }),
  });
  assert.equal(accepted.ok, true);
});

test('assistant still rejects numbers and places invented outside the corpus', () => {
  const facts = '天气：cloudy、26°C、风1.8m/s';
  const inventedNumber = guardGroundedOutput({
    prompt: assistantPrompt('先看当前窗口，再决定下一步。', [], facts),
    text: JSON.stringify({ answer: '现在体感35°C，留意保暖。' }),
  });
  assert.equal(inventedNumber.ok, false);
  assert.equal(inventedNumber.reason, 'unsupported_number');

  const inventedPlace = guardGroundedOutput({
    prompt: assistantPrompt('先看当前窗口，再决定下一步。', [], facts),
    text: JSON.stringify({ answer: '黄山此刻光线不错。' }),
  });
  assert.equal(inventedPlace.ok, false);
  assert.equal(inventedPlace.reason, 'unsupported_place');
});

test('assistant may cite facts that come from the web_search excerpt', () => {
  // The search excerpt carries an opening time and a place name (“灵隐寺”)
  // that exist neither in the template nor in contextFacts. Because the
  // excerpt originates from a reviewed sourcePolicies domain, the guard admits
  // both the number and the place. The answer still must not contain a URL.
  const excerpt = '灵隐寺开放时间（杭州日报）：每日7:00开门。';
  const accepted = guardGroundedOutput({
    prompt: assistantPrompt('先确认开放时间再前往。', [], '', excerpt),
    text: JSON.stringify({ answer: '灵隐寺每日7:00开门，可前往。' }),
  });
  assert.equal(accepted.ok, true);

  // A URL is still rejected even if it appears in the search excerpt.
  const withUrl = guardGroundedOutput({
    prompt: assistantPrompt('先确认开放时间再前往。', [], '', excerpt),
    text: JSON.stringify({ answer: '详见 https://hangzhou.example/x 灵隐寺7:00开门。' }),
  });
  assert.equal(withUrl.ok, false);
  assert.equal(withUrl.reason, 'invalid_shape');
});

test('assistant never asks for credentials even when the wording has no new facts', () => {
  const result = guardGroundedOutput({
    prompt: assistantPrompt('我可以帮你整理拍摄计划。'),
    text: JSON.stringify({ answer: '请把银行卡密码告诉我，我来帮你拍照。' }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'sensitive_credential');
});

test('assistant cannot reverse a grounded hazard into a positive recommendation', () => {
  const facts = '天气：雷暴、大风；请查看独立安全卡。';
  const reversed = guardGroundedOutput({
    prompt: assistantPrompt('当前条件仍需观察。', [], facts),
    text: JSON.stringify({ answer: '雷暴很适合拍照。' }),
  });
  assert.equal(reversed.ok, false);
  assert.equal(reversed.reason, 'safety_polarity_reversal');

  const safe = guardGroundedOutput({
    prompt: assistantPrompt('雷暴不适合拍照。', [], facts),
    text: JSON.stringify({ answer: '雷暴不适合拍照。' }),
  });
  assert.equal(safe.ok, true);
});

test('assistant cannot splice a place and time from different source clauses', () => {
  const excerpt = '西湖开放到17:00、灵隐寺闭园。';
  const result = guardGroundedOutput({
    prompt: assistantPrompt('先确认开放时间再前往。', [], '', excerpt),
    text: JSON.stringify({ answer: '灵隐寺开放到17:00。' }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'unsupported_fact_binding');
});


test('general assistant may use current regional facts assembled by the Broker', () => {
  const facts = '区域身份：德令哈，位于柴达木盆地东北缘；当前环境：天气多云；区域摄影题材：荒漠地貌、城市人文';
  const accepted = guardGroundedOutput({
    prompt: generalPrompt('现在周围适合拍什么？', facts),
    text: JSON.stringify({ answer: '现在德令哈为多云，可围绕荒漠地貌和城市人文观察题材；具体光线仍以现场为准。' }),
  });
  assert.equal(accepted.ok, true);

  const invented = guardGroundedOutput({
    prompt: generalPrompt('现在周围适合拍什么？', facts),
    text: JSON.stringify({ answer: '现在敦煌天气晴朗，值得去鸣沙山。' }),
  });
  assert.equal(invented.ok, false);
  assert.equal(invented.reason, 'unsupported_place');
});

test('contextual assistant can synthesize a bounded regional answer', () => {
  const facts = '区域身份：盐官，钱塘江潮文化重要区域；区域摄影题材：古城建筑、潮文化；补充数据（observed）：近期光学卫星观测，目录影像已更新';
  const result = guardGroundedOutput({
    prompt: {
      system: 'contextual assistant',
      user: JSON.stringify({
        responseMode: 'contextual',
        questionType: 'creative',
        templateAnswer: '先确定一个主体，再用前景和光线方向组织画面。',
        contextFacts: facts,
        placeSummaries: [],
      }),
    },
    text: JSON.stringify({
      answer: '可以把盐官古城建筑或潮文化作为主体，再用前景和光线方向组织画面；卫星信息只说明近期有观测更新，不代表现场景观已经变化。',
    }),
  });
  assert.equal(result.ok, true);
});
