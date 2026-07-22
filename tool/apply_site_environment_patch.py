from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one match in {path}, found {count}: {old[:80]!r}")
    file.write_text(text.replace(old, new, 1))


server_path = "services/lumanest-data-broker/src/server.mjs"

replace_once(
    server_path,
    """import {
  SevenTimerService,
  validSevenTimerRequest,
} from './providers/seven_timer/seven_timer_provider.mjs';
""",
    """import {
  SevenTimerService,
  validSevenTimerRequest,
} from './providers/seven_timer/seven_timer_provider.mjs';
import {
  SiteEnvironmentService,
  validSiteEnvironmentQuery,
} from './environment/site-environment-service.mjs';
""",
)

replace_once(
    server_path,
    """  { path: '/v1/elevation/profile', limit: 20, windowMs: 60 * 1_000, key: 'elevation' },
""",
    """  { path: '/v1/elevation/profile', limit: 20, windowMs: 60 * 1_000, key: 'elevation' },
  { path: '/v1/environment/site-facts', limit: 20, windowMs: 60 * 1_000, key: 'site-environment' },
""",
)

replace_once(
    server_path,
    """  sevenTimerMetrics = new SevenTimerMetrics(),
  sevenTimerService = null,
  requestRateLimiter = new MemoryRequestRateLimiter(),
""",
    """  sevenTimerMetrics = new SevenTimerMetrics(),
  sevenTimerService = null,
  rasterServiceUrl = '',
  siteEnvironmentService = null,
  requestRateLimiter = new MemoryRequestRateLimiter(),
""",
)

replace_once(
    server_path,
    """    sunsetBotBaseUrl,
    sevenTimerBaseUrl,
    settings: validateRuntimeSettings(settings ?? {}),
""",
    """    sunsetBotBaseUrl,
    sevenTimerBaseUrl,
    rasterServiceUrl,
    settings: validateRuntimeSettings(settings ?? {}),
""",
)

replace_once(
    server_path,
    """  const activeSevenTimerMetrics = activeSevenTimerService.metrics ?? sevenTimerMetrics;
  const wildlifeCache = new Map();
""",
    """  const activeSevenTimerMetrics = activeSevenTimerService.metrics ?? sevenTimerMetrics;
  const activeSiteEnvironmentService = siteEnvironmentService ?? new SiteEnvironmentService({
    rasterServiceUrl,
    fetcher,
    now,
    timeoutMs: Math.min(configurationSource.snapshot().settings.upstreamTimeoutMs, 8_000),
  });
  const wildlifeCache = new Map();
""",
)

replace_once(
    server_path,
    """    if (request.method === 'GET' && requestUrl.pathname === '/metrics') {
""",
    """    if (request.method === 'GET' && requestUrl.pathname === '/v1/environment/site-facts') {
      const query = validSiteEnvironmentQuery(requestUrl.searchParams);
      if (query == null) {
        writeJson(response, 400, { error: 'invalid_site_environment_query' });
        return;
      }
      writeJson(response, 200, await activeSiteEnvironmentService.facts(query));
      return;
    }

    if (request.method === 'GET' && requestUrl.pathname === '/metrics') {
""",
)

replace_once(
    server_path,
    """    sevenTimerBaseUrl: environment.SEVEN_TIMER_BASE_URL?.trim() || 'https://www.7timer.info',
    port: Number.parseInt(environment.PORT ?? '8787', 10),
""",
    """    sevenTimerBaseUrl: environment.SEVEN_TIMER_BASE_URL?.trim() || 'https://www.7timer.info',
    rasterServiceUrl: environment.LUMANEST_RASTER_SERVICE_URL?.trim() ?? '',
    port: Number.parseInt(environment.PORT ?? '8787', 10),
""",
)

replace_once(
    server_path,
    """    sevenTimerBaseUrl: defaults.sevenTimerBaseUrl,
    skyOpportunityCache,
""",
    """    sevenTimerBaseUrl: defaults.sevenTimerBaseUrl,
    rasterServiceUrl: defaults.rasterServiceUrl,
    skyOpportunityCache,
""",
)
