function frozenRanges(entries) {
  return Object.freeze(Object.fromEntries(entries.map(([level, minimum, maximum]) => [
    level,
    Object.freeze({ minimum, maximum }),
  ])));
}

export const cloudCoverRanges = frozenRanges([
  [1, 0, 6], [2, 6, 19], [3, 19, 31], [4, 31, 44], [5, 44, 56],
  [6, 56, 69], [7, 69, 81], [8, 81, 94], [9, 94, 100],
]);

export const windSpeedRanges = frozenRanges([
  [1, 0, .3], [2, .3, 3.4], [3, 3.4, 8], [4, 8, 10.8],
  [5, 10.8, 17.2], [6, 17.2, 24.5], [7, 24.5, 32.6], [8, 32.6, null],
]);

export const meteoWindSpeedRanges = frozenRanges([
  [1, 0, .3], [2, .3, 3.4], [3, 3.4, 8], [4, 8, 10.8],
  [5, 10.8, 17.2], [6, 17.2, 24.5], [7, 24.5, 32.6], [8, 32.6, 36.7],
  [9, 36.7, 41.4], [10, 41.4, 46.2], [11, 46.2, 50.9],
  [12, 50.9, 55.9], [13, 55.9, null],
]);

export const seeingRanges = frozenRanges([
  [1, null, .5], [2, .5, .75], [3, .75, 1], [4, 1, 1.25],
  [5, 1.25, 1.5], [6, 1.5, 2], [7, 2, 2.5], [8, 2.5, null],
]);

export const transparencyRanges = frozenRanges([
  [1, null, .3], [2, .3, .4], [3, .4, .5], [4, .5, .6],
  [5, .6, .7], [6, .7, .85], [7, .85, 1], [8, 1, null],
]);

export const humidityRanges = frozenRanges([
  [-4, 0, 5], [-3, 5, 10], [-2, 10, 15], [-1, 15, 20], [0, 20, 25],
  [1, 25, 30], [2, 30, 35], [3, 35, 40], [4, 40, 45], [5, 45, 50],
  [6, 50, 55], [7, 55, 60], [8, 60, 65], [9, 65, 70], [10, 70, 75],
  [11, 75, 80], [12, 80, 85], [13, 85, 90], [14, 90, 95], [15, 95, 99],
  [16, 100, 100],
]);

export const precipitationAmountRanges = frozenRanges([
  [0, 0, 0], [1, 0, .25], [2, .25, 1], [3, 1, 4], [4, 4, 10],
  [5, 10, 16], [6, 16, 30], [7, 30, 50], [8, 50, 75], [9, 75, null],
]);

export const snowDepthRanges = frozenRanges([
  [0, 0, 0], [1, 0, 1], [2, 1, 5], [3, 5, 10], [4, 10, 25],
  [5, 25, 50], [6, 50, 100], [7, 100, 150], [8, 150, 250], [9, 250, null],
]);

export function mappedRange(level, ranges, unit) {
  if (!Number.isInteger(level) || !Object.hasOwn(ranges, level)) return null;
  const range = ranges[level];
  return {
    level,
    min: range.minimum,
    max: range.maximum,
    unit,
  };
}
