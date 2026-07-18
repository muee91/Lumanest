export function opportunityLevel(score) {
  if (!Number.isFinite(score)) return { level: 'unavailable', label: '暂无判断' };
  if (score <= .001) return { level: 'none', label: '条件有限' };
  if (score < .05) return { level: 'trace', label: '可留意天色变化' };
  if (score < .20) return { level: 'weak', label: '条件偏弱' };
  if (score < .40) return { level: 'moderate', label: '有机会，仍需观察' };
  if (score < .60) return { level: 'good', label: '值得留意' };
  if (score < .80) return { level: 'strong', label: '条件较好' };
  if (score < 1) return { level: 'very_strong', label: '条件很好' };
  if (score < 1.5) return { level: 'excellent', label: '光色条件突出' };
  if (score < 2) return { level: 'rare', label: '光色条件很突出' };
  return { level: 'exceptional', label: '条件少见，保持观察' };
}

export function clarityLevel(aod) {
  if (!Number.isFinite(aod)) {
    return { clarityLevel: 'unknown', clarityLabel: '暂无通透度数据' };
  }
  if (aod <= .10) return { clarityLevel: 'crystal', clarityLabel: '大气非常通透' };
  if (aod <= .20) return { clarityLevel: 'very_good', clarityLabel: '天空通透' };
  if (aod <= .30) return { clarityLevel: 'good', clarityLabel: '大气较通透' };
  if (aod <= .40) return { clarityLevel: 'normal', clarityLabel: '通透度一般' };
  if (aod <= .60) return { clarityLevel: 'hazy', clarityLabel: '空气略浑浊' };
  if (aod <= .80) return { clarityLevel: 'poor', clarityLabel: '大气偏灰' };
  return { clarityLevel: 'very_poor', clarityLabel: '大气非常浑浊' };
}
