# LumaNest Raster Service

This private service samples reviewed geospatial rasters for the Data Broker. It
currently exposes annual VIIRS nighttime-light radiance and bounded spatial
radiance analysis. It does **not** convert satellite radiance into a Bortle class
or an observing-success probability.

## Required data

Mount an Earth Observation Group annual VIIRS V2.2 GeoTIFF into the container.
Prefer a `median-masked` annual layer; use `average-masked` only when the median
layer is unavailable. The source product is approximately 15 arc-seconds
(~500 m at the equator) and reports radiance in `nW/cm²/sr`.

The raster file is deployment data and must not be committed to Git. Replace it
through a versioned directory or atomic symlink switch rather than overwriting a
file that the service is reading.

## Environment

Raster service:

```text
VIIRS_RASTER_PATH=/data/viirs/current/median-masked.tif
VIIRS_DATASET_YEAR=2024
VIIRS_DATASET_REVISION=eog-v2.2-2024-median-masked-r1
VIIRS_SOURCE_ID=eog-viirs-annual-v2.2
VIIRS_ATTRIBUTION=Earth Observation Group VIIRS annual nighttime lights
VIIRS_RESOLUTION_METERS=500
RASTER_SERVICE_TOKEN=<private-random-token>
```

Data Broker:

```text
LUMANEST_RASTER_SERVICE_URL=http://lumanest-raster-service:8792
LUMANEST_RASTER_SERVICE_TOKEN=<same-private-random-token>
LUMANEST_RASTER_DATASET_REVISION=eog-v2.2-2024-median-masked-r1
```

`LUMANEST_RASTER_DATASET_REVISION` pins Broker cache keys and rejects responses
from an unexpected raster revision. Update the Raster service and Broker values
together when promoting a new annual dataset.

The Raster service should be reachable only on the private container network.
Do not publish port `8792` to the public internet.

## Run

```bash
docker build -t lumanest-raster-service services/lumanest-raster-service
docker run --rm \
  --network lumanest-internal \
  -v /srv/lumanest/viirs:/data/viirs:ro \
  -e VIIRS_RASTER_PATH=/data/viirs/current/median-masked.tif \
  -e VIIRS_DATASET_YEAR=2024 \
  -e VIIRS_DATASET_REVISION=eog-v2.2-2024-median-masked-r1 \
  -e RASTER_SERVICE_TOKEN="$RASTER_SERVICE_TOKEN" \
  lumanest-raster-service
```

## API

```text
GET /healthz
GET /v1/viirs/sample?latitude=30.25&longitude=120.15
Authorization: Bearer <RASTER_SERVICE_TOKEN>
```

`/healthz` performs eager dataset validation and reports whether the file can be
opened, has a CRS, contains a numeric band, has valid dimensions and bounds, and
has internal authentication configured. It also reports the active dataset
revision and spatial-analysis version without exposing user coordinates.

A valid sample returns:

- raw radiance at the sampled pixel center;
- 1 km, 5 km, and 20 km circular-neighborhood median, P90, maximum, sample count,
  and valid-data coverage ratio;
- eight directional sectors over the 1–20 km ring;
- the dominant light-dome direction, sector P90, maximum, coverage, and peak-light
  distance;
- source and dataset revision metadata.

The directional result describes the distribution of satellite-observed upward
radiance around a site. It is evidence for likely sky-glow direction, not a
terrain-aware sky-brightness measurement. DEM horizon analysis must be applied
separately before using it in a photography recommendation.

Missing files, invalid datasets, out-of-coverage coordinates, NoData pixels,
invalid raster values, and authentication failures return bounded non-200
responses so the Broker can degrade light pollution independently from elevation
and weather.
