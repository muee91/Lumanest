import assert from 'node:assert/strict';
import test from 'node:test';

import {
  cleanSunsetBotHtml,
  parseProviderEventTime,
  parseProviderNumeric,
  parseSunsetBotResponse,
} from '../src/providers/sunsetbot/sunsetbot_parser.mjs';
import { mapEventCode } from '../src/providers/sunsetbot/sunsetbot_provider.mjs';

test('maps only supported sunrise and sunset event codes', () => {
  assert.equal(mapEventCode('sunrise', 0), 'rise_1');
  assert.equal(mapEventCode('sunset', 0), 'set_1');
  assert.equal(mapEventCode('sunrise', 1), 'rise_2');
  assert.equal(mapEventCode('sunset', 1), 'set_2');
  assert.equal(mapEventCode('sunset', 2), null);
  assert.equal(mapEventCode('rainbow', 0), null);
});

test('cleans br tags, other HTML, entities and repeated whitespace', () => {
  assert.equal(
    cleanSunsetBotHtml('  0.291<br /> <strong>（小烧到中烧）</strong>&nbsp; '),
    '0.291 （小烧到中烧）',
  );
});

test('parses quality and AOD without inventing zero', () => {
  assert.deepEqual(parseProviderNumeric('0.291<br>（小烧到中烧）'), {
    value: .291,
    providerLabel: '小烧到中烧',
    valid: true,
  });
  assert.deepEqual(parseProviderNumeric('暂无'), {
    value: null,
    providerLabel: '暂无',
    valid: false,
  });
});

test('parses provider time in Asia Shanghai and preserves invalid raw text', () => {
  assert.deepEqual(parseProviderEventTime('2026-07-18 18:59:55'), {
    eventTime: '2026-07-18T18:59:55+08:00',
    rawEventTime: '2026-07-18 18:59:55',
  });
  assert.deepEqual(parseProviderEventTime('2026-02-30 18:59:55'), {
    eventTime: null,
    rawEventTime: '2026-02-30 18:59:55',
  });
});

test('tolerates missing fields and marks partial parsing', () => {
  const parsed = parseSunsetBotResponse({ status: 'ok', tb_quality: '', tb_aod: null }, {
    model: 'GFS',
  });
  assert.equal(parsed.status, 'ok');
  assert.equal(parsed.parseStatus, 'partial');
  assert.equal(parsed.score, null);
  assert.equal(parsed.aod, null);
});

test('parses the documented response without exposing HTML', () => {
  const parsed = parseSunsetBotResponse({
    status: 'ok',
    tb_event_time: '2026-07-18 18:59:55',
    tb_quality: '0.291<br>（小烧到中烧）',
    tb_aod: '0.244<br>（还不错）',
  }, { model: 'GFS' });
  assert.equal(parsed.score, .291);
  assert.equal(parsed.providerLabel, '小烧到中烧');
  assert.equal(parsed.aod, .244);
  assert.equal(parsed.aodLabel, '还不错');
  assert.equal(parsed.eventTime, '2026-07-18T18:59:55+08:00');
});

test('rejects implausible numeric fields instead of turning an upstream error into a top opportunity', () => {
  const parsed = parseSunsetBotResponse({
    status: 'ok',
    tb_event_time: '2026-07-18 18:59:55',
    tb_quality: '999 服务器错误',
    tb_aod: '-2',
  }, { model: 'EC' });
  assert.equal(parsed.parseStatus, 'invalid_numeric_field');
  assert.equal(parsed.score, null);
  assert.equal(parsed.aod, null);
});
