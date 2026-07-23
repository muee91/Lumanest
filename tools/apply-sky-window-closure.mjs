import { readFileSync, writeFileSync } from 'node:fs';

const path = 'services/lumanest-data-broker/src/server.mjs';
let source = readFileSync(path, 'utf8');

function replaceOnce(before, after, label) {
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`Expected exactly one ${label} anchor`);
  }
  source = source.slice(0, first) + after + source.slice(first + before.length);
}

replaceOnce(
`import {
  SiteEnvironmentService,
  validSiteEnvironmentQuery,
} from './environment/site-environment-service.mjs';
`,
`import {
  SiteEnvironmentService,
  validSiteEnvironmentQuery,
} from './environment/site-environment-service.mjs';
import { OpenMeteoNightSkyForecast } from './environment/open-meteo-night-sky.mjs';
import { SkyBrightnessCalibrationStore } from './environment/sky-brightness-calibration.mjs';
import { SkyWindowService, validSkyWindowQuery } from './environment/sky-window-service.mjs';
`,
'import anchor',
);

replaceOnce(
`  rasterServiceUrl = '',
  siteEnvironmentService = null,
  requestRateLimiter = new MemoryRequestRateLimiter(),
`,
`  rasterServiceUrl = '',
  siteEnvironmentService = null,
  openMeteoForecastBaseUrl = 'https://api.open-meteo.com',
  skyBrightnessCalibrationPath = '',
  skyWindowService = null,
  requestRateLimiter = new MemoryRequestRateLimiter(),
`,
'constructor arguments',
);

replaceOnce(
`    sevenTimerBaseUrl,
    rasterServiceUrl,
    settings: validateRuntimeSettings(settings ?? {}),
`,
`    sevenTimerBaseUrl,
    rasterServiceUrl,
    openMeteoForecastBaseUrl,
    skyBrightnessCalibrationPath,
    settings: validateRuntimeSettings(settings ?? {}),
`,
'fixed configuration',
);

replaceOnce(
`  const activeSiteEnvironmentService = siteEnvironmentService ?? new SiteEnvironmentService({
    rasterServiceUrl,
    fetcher,
    now,
    timeoutMs: Math.min(configurationSource.snapshot().settings.upstreamTimeoutMs, 8_000),
  });
`,
`  const activeSiteEnvironmentService = siteEnvironmentService ?? new SiteEnvironmentService({
    rasterServiceUrl,
    fetcher,
    now,
    timeoutMs: Math.min(configurationSource.snapshot().settings.upstreamTimeoutMs, 8_000),
  });
  const activeOpenMeteoForecast = new OpenMeteoNightSkyForecast({
    baseUrl: openMeteoForecastBaseUrl,
    fetcher,
    now,
    timeoutMs: Math.min(configurationSource.snapshot().settings.upstreamTimeoutMs, 8_000),
  });
  const activeCalibrationStore = SkyBrightnessCalibrationStore.fromFile(
    skyBrightnessCalibrationPath,
  );
  const activeSkyWindowService = skyWindowService ?? new SkyWindowService({
    siteEnvironmentService: activeSiteEnvironmentService,
    openMeteoForecast: activeOpenMeteoForecast,
    sevenTimerService: activeSevenTimerService,
    calibrationStore: activeCalibrationStore,
    now,
  });
`,
'service construction',
);

replaceOnce(
`    if (request.method === 'GET' && requestUrl.pathname === '/v1/environment/site-facts') {
      const query = validSiteEnvironmentQuery(requestUrl.searchParams);
      if (query == null) {
        writeJson(response, 400, { error: 'invalid_site_environment_query' });
        return;
      }
      writeJson(response, 200, await activeSiteEnvironmentService.facts(query));
      return;
    }
`,
`    if (request.method === 'GET' && requestUrl.pathname === '/v1/environment/site-facts') {
      const query = validSiteEnvironmentQuery(requestUrl.searchParams);
      if (query == null) {
        writeJson(response, 400, { error: 'invalid_site_environment_query' });
        return;
      }
      writeJson(response, 200, await activeSiteEnvironmentService.facts(query));
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/v1/environment/sky-windows') {
      const query = validSkyWindowQuery(requestUrl.searchParams, now());
      if (query == null) {
        writeJson(response, 400, { error: 'invalid_sky_window_query' });
        return;
      }
      writeJson(response, 200, await activeSkyWindowService.forecast(query));
      return;
    }
`,
'route insertion',
);

replaceOnce(
`    sevenTimerBaseUrl: environment.SEVEN_TIMER_BASE_URL?.trim() || 'https://www.7timer.info',
    rasterServiceUrl: environment.LUMANEST_RASTER_SERVICE_URL?.trim() ?? '',
    port: Number.parseInt(environment.PORT ?? '8787', 10),
`,
`    sevenTimerBaseUrl: environment.SEVEN_TIMER_BASE_URL?.trim() || 'https://www.7timer.info',
    rasterServiceUrl: environment.LUMANEST_RASTER_SERVICE_URL?.trim() ?? '',
    openMeteoForecastBaseUrl: environment.OPEN_METEO_FORECAST_BASE_URL?.trim() || 'https://api.open-meteo.com',
    skyBrightnessCalibrationPath: environment.LUMANEST_SKY_BRIGHTNESS_CALIBRATION_PATH?.trim() ?? '',
    port: Number.parseInt(environment.PORT ?? '8787', 10),
`,
'environment configuration',
);

replaceOnce(
`    sevenTimerBaseUrl: defaults.sevenTimerBaseUrl,
    rasterServiceUrl: defaults.rasterServiceUrl,
    skyOpportunityCache,
`,
`    sevenTimerBaseUrl: defaults.sevenTimerBaseUrl,
    rasterServiceUrl: defaults.rasterServiceUrl,
    openMeteoForecastBaseUrl: defaults.openMeteoForecastBaseUrl,
    skyBrightnessCalibrationPath: defaults.skyBrightnessCalibrationPath,
    skyOpportunityCache,
`,
'broker service wiring',
);

writeFileSync(path, source);
