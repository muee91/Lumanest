# Sky Window Forecast

The Broker exposes an authenticated, on-demand night-sky forecast that combines
public weather evidence, local ephemerides, reviewed terrain and light-pollution
rasters, and optional ground observations.

## Endpoint

```text
GET /v1/environment/sky-windows
  ?lat=30.25
  &lon=100.15
  &start=2026-07-23T15:00:00.000Z
  &hours=72
  &locale=zh-CN
Authorization: Bearer <LUMANEST_SERVICE_TOKEN>
```

`start` must be UTC and end in `Z`. The request accepts 6–72 hours and evaluates
the interval at fixed 15-minute steps. The response contains the current
assessment, at most eight continuous candidate windows, one best-window
reference when available, source readiness, conflicts and optional nearby ground
calibration.

## Runtime evidence

- Astronomy Engine 2.1.19: local Sun and Moon horizon position, lunar
  illumination and phase. No JPL network request occurs at runtime.
- Galactic Center J2000 geometry: local deterministic horizontal coordinates.
- Open-Meteo Best Match: total/low/middle/high cloud cover, visibility,
  precipitation probability and amount, humidity, wind and gusts.
- 7Timer astro: auxiliary cloud, seeing, transparency and humidity evidence.
  Disagreement with Open-Meteo is surfaced rather than silently averaged.
- Copernicus GLO-30: terrain horizon and directional clearance.
- EOG VIIRS: directional relative radiance and light-dome evidence.
- Optional normalized ground observations: nearby median SQM or naked-eye
  limiting magnitude, with source, licence, observation period and sample count.

## Condition policy

The public contract returns qualitative bands only:

```text
favorable
conditional
unavailable
insufficientData
```

Hard blockers include daylight/twilight, the Galactic Center below the geometric
or terrain horizon, likely precipitation, nearly complete cloud cover, very poor
visibility and blocking gusts. Moderate cloud, limited visibility, small terrain
clearance, Moon interference, directional light pollution or conflicting
forecast sources produce a conditional result. Missing critical evidence
produces insufficient data.

The service does not return observing-success probability and does not convert
VIIRS radiance or citizen observations into a precise Bortle value.

## Ground calibration bundle

Raw public downloads must be reviewed for provenance and licence, then converted
to this normalized CSV shape:

```text
latitude,longitude,observed_at,sqm_mag_per_arcsec2,limiting_magnitude
```

Either measurement field may be empty, but each accepted row needs a valid UTC
observation time and coordinate. Build the deployment bundle from the Broker
directory:

```bash
npm run build:sky-calibration -- \
  /data/import/ground-sky.csv \
  /data/sky/calibration.json \
  public-ground-sky-r1 \
  "Normalized public SQM and Globe at Night observations" \
  "Contributing observers and source datasets" \
  "reviewed-source-licences"
```

The builder groups records into 0.05-degree cells, keeps medians and observation
ranges, and drops cells with fewer than three accepted observations. Mount the
JSON read-only and configure:

```text
LUMANEST_SKY_BRIGHTNESS_CALIBRATION_PATH=/data/sky/calibration.json
```

No calibration file is required for the primary forecast. Missing or distant
observations lower confidence or remain unavailable without blocking the weather,
terrain, Moon or VIIRS chains.

## Deployment

The Broker image must be rebuilt with the standard Dockerfile because
`package-lock.json` now includes Astronomy Engine. Do not use the cached
source-only deployment path for this release.

Open-Meteo and 7Timer require outbound HTTPS access. Terrain and VIIRS remain
private services with reviewed raster mounts and matching dataset revisions.
