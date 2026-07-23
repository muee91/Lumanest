# LumaNest Terrain Service

Private service for sampling a reviewed Copernicus DEM GLO-30 GeoTIFF and
producing a cached-ready 360-degree terrain horizon profile. The service uses a
fixed 5-degree azimuth step, a 40 km maximum radius, a 1.7 m observer height,
and a bounded standard-refraction coefficient. It does not claim survey-grade
accuracy and exposes data coverage with every profile.

## Environment

Terrain service:

```text
DEM_RASTER_PATH=/data/dem/current/copernicus-glo30.tif
DEM_DATASET_REVISION=copernicus-glo30-2024-r1
DEM_SOURCE_ID=copernicus-dem-glo30
DEM_ATTRIBUTION=Copernicus DEM GLO-30
DEM_RESOLUTION_METERS=30
TERRAIN_SERVICE_TOKEN=<private-random-token>
```

Data Broker:

```text
LUMANEST_TERRAIN_SERVICE_URL=http://lumanest-terrain-service:8793
LUMANEST_TERRAIN_SERVICE_TOKEN=<same-private-random-token>
LUMANEST_TERRAIN_DATASET_REVISION=copernicus-glo30-2024-r1
```

The DEM file is deployment data and must not be committed to Git. Promote a
new dataset through a versioned directory or atomic symlink switch, then update
the Terrain service and Broker revisions together. Keep port `8793` on the
private container network.

## API

```text
GET /healthz
GET /v1/dem/horizon?latitude=30.25&longitude=120.15
Authorization: Bearer <TERRAIN_SERVICE_TOKEN>
```

The horizon endpoint returns observer DEM elevation, per-direction terrain
altitude, obstruction distance and elevation, per-direction coverage, and the
overall profile coverage. Copernicus GLO-30 is a DSM; vegetation and structures
may influence the result.

The public Broker keeps its existing Contract V3 response unless the client
explicitly requests `include=skyAssessment` with a UTC `at` timestamp. That
request returns Contract V4 with the terrain horizon and a direction-aware
assessment. The assessment does not include a Bortle conversion or success
probability.
