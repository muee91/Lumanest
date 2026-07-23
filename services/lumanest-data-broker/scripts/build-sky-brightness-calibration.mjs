import { readFileSync, writeFileSync } from 'node:fs';

function parseCsv(text) {
  const rows = [];
  let row = [];
  let value = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') {
        value += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        value += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ',') {
      row.push(value);
      value = '';
    } else if (character === '\n') {
      row.push(value.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      value = '';
    } else {
      value += character;
    }
  }
  if (quoted) throw new Error('Unterminated CSV quote');
  if (value.length > 0 || row.length > 0) {
    row.push(value.replace(/\r$/, ''));
    rows.push(row);
  }
  return rows;
}

function finite(value, minimum, maximum) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= minimum && parsed <= maximum ? parsed : null;
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const center = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[center - 1] + sorted[center]) / 2 : sorted[center];
}

function requiredArgument(index, label) {
  const value = process.argv[index]?.trim();
  if (!value) throw new Error(`Missing ${label}`);
  return value;
}

const inputPath = requiredArgument(2, 'input CSV path');
const outputPath = requiredArgument(3, 'output JSON path');
const datasetId = requiredArgument(4, 'dataset id');
const source = requiredArgument(5, 'source label');
const attribution = requiredArgument(6, 'attribution');
const license = requiredArgument(7, 'license identifier');
const rows = parseCsv(readFileSync(inputPath, 'utf8'));
if (rows.length < 2) throw new Error('Calibration CSV is empty');
const headers = rows[0].map((name) => name.trim());
const requiredHeaders = ['latitude', 'longitude', 'observed_at', 'sqm_mag_per_arcsec2', 'limiting_magnitude'];
for (const header of requiredHeaders) {
  if (!headers.includes(header)) throw new Error(`Missing required column: ${header}`);
}
const index = Object.fromEntries(headers.map((name, position) => [name, position]));
const groups = new Map();
for (const row of rows.slice(1)) {
  const latitude = finite(row[index.latitude], -90, 90);
  const longitude = finite(row[index.longitude], -180, 180);
  const observedAt = new Date(row[index.observed_at]);
  const sqm = row[index.sqm_mag_per_arcsec2]?.trim() === ''
    ? null
    : finite(row[index.sqm_mag_per_arcsec2], 10, 30);
  const limitingMagnitude = row[index.limiting_magnitude]?.trim() === ''
    ? null
    : finite(row[index.limiting_magnitude], -2, 9);
  if (latitude == null || longitude == null || !Number.isFinite(observedAt.getTime()) ||
      (sqm == null && limitingMagnitude == null)) continue;
  const cellLatitude = Math.round(latitude * 20) / 20;
  const cellLongitude = Math.round(longitude * 20) / 20;
  const key = `${cellLatitude.toFixed(2)}:${cellLongitude.toFixed(2)}`;
  const group = groups.get(key) ?? {
    latitude: cellLatitude,
    longitude: cellLongitude,
    observations: [],
  };
  group.observations.push({ observedAt, sqm, limitingMagnitude });
  groups.set(key, group);
}
const cells = [...groups.values()].map((group) => {
  const dates = group.observations.map((item) => item.observedAt).sort((a, b) => a - b);
  return {
    latitude: group.latitude,
    longitude: group.longitude,
    sampleCount: group.observations.length,
    sqmMedian: median(group.observations.flatMap((item) => item.sqm == null ? [] : [item.sqm])),
    limitingMagnitudeMedian: median(
      group.observations.flatMap((item) => item.limitingMagnitude == null ? [] : [item.limitingMagnitude]),
    ),
    observedFrom: dates[0].toISOString(),
    observedTo: dates.at(-1).toISOString(),
  };
}).filter((cell) => cell.sampleCount >= 3)
  .sort((a, b) => a.latitude - b.latitude || a.longitude - b.longitude);
const output = {
  contractVersion: 1,
  dataset: {
    id: datasetId,
    source,
    attribution,
    license,
    generatedAt: new Date().toISOString(),
  },
  cells,
};
writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`);
console.log(`Wrote ${cells.length} calibration cells to ${outputPath}`);
