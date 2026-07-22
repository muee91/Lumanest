# LumaNest Raster Service

This private service samples reviewed geospatial rasters for the Data Broker. It
currently exposes annual VIIRS nighttime-light radiance. It does **not** convert
satellite radiance into a Bortle class or an observing-success probability.

## Required data

Mount an Earth Observation Group annual VIIRS V2.2 GeoTIFF into the container.
Use an `average-masked` or `median-masked` annual layer in EPSG:4326. The source
product is approximately 15 arc-seconds (~500 m at the equator) and reports
radiance in `nW/cm²/sr`.

The raster file is deployment data and must not be committed to Git.

## Environment

```text
VIIRS_RASTER_PATH=/data/viirs/annual-v22-average-masked.tif
VIIRS_DATASET_YEAR=2024
VIIRS_SOURCE_ID=eog-viirs-annual-v2.2
VIIRS_ATTRIBUTION=Earth Observation Group VIIRS annual nighttime lights
VIIRS_RESOLUTION_METERS=500
```

The Data Broker must use:

```text
LUMANEST_RASTER_SERVICE_URL=http://lumanest-raster-service:8792
```

## Run

```bash
docker build -t lumanest-raster-service services/lumanest-raster-service
docker run --rm -p 8792:8792 \
  -v /srv/lumanest/viirs:/data/viirs:ro \
  -e VIIRS_RASTER_PATH=/data/viirs/annual-v22-average-masked.tif \
  -e VIIRS_DATASET_YEAR=2024 \
  lumanest-raster-service
```

## API

```text
GET /healthz
GET /v1/viirs/sample?latitude=30.25&longitude=120.15
```

A valid sample returns raw annual radiance and source metadata. Missing files,
out-of-coverage coordinates, NoData pixels, and invalid raster values return a
bounded non-200 response so the Broker can degrade light pollution independently
from elevation and weather.
