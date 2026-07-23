# LumaNest Terrain Service

Private service for sampling a reviewed Copernicus DEM GLO-30 GeoTIFF and
producing a cached-ready 360-degree terrain horizon profile. The service uses a
fixed 5-degree azimuth step, a 40 km maximum radius, a 1.7 m observer height,
and a bounded standard-refraction coefficient. It does not claim survey-grade
accuracy and exposes data coverage with every profile.

## Environment

```text
DEM_RASTER_PATH=/data/dem/current/copernicus-glo30.tif
DEM_DATASET_REVISION=copernicus-glo30-2024-r1
DEM_SOURCE_ID=copernicus-dem-glo30
DEM_ATTRIBUTION=Copernicus DEM GLO-30
DEM_RESOLUTION_METERS=30
TERRAIN_SERVICE_TOKEN=<private-random-token>
```

The DEM file is deployment data and must not be committed to Git. Promote a
new dataset through a versioned directory or atomic symlink switch, then update
the Broker's expected revision at the same time.

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
