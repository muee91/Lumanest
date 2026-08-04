from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"{label}: expected one anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


route_path = Path('lib/src/presentation_v2/route/v2_route_page.dart')
route = route_path.read_text()
route = replace_once(
    route,
    "import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';\n"
    "import 'package:luma_nest/src/features/route/domain/driving_route.dart';",
    "import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';\n"
    "import 'package:luma_nest/src/features/route/application/route_navigation_launcher.dart';\n"
    "import 'package:luma_nest/src/features/route/application/route_scout_providers.dart';\n"
    "import 'package:luma_nest/src/features/route/domain/driving_route.dart';\n"
    "import 'package:luma_nest/src/features/route/domain/route_scout_plan.dart';",
    'route imports',
)
route = replace_once(
    route,
    "    final quietMode = active;\n"
    "    final points = widget.route.polyline",
    "    final quietMode = active;\n"
    "    final now = ref.watch(currentTimeProvider)();\n"
    "    final scout = ref.watch(routeScoutPlanProvider(_scoutRequest));\n"
    "    final activeJourney = active ? library?.activeJourney : null;\n"
    "    final journeyProgress = activeJourney == null\n"
    "        ? 0.0\n"
    "        : RouteScoutPlan.progressForJourney(\n"
    "            startedAt: activeJourney.startedAt,\n"
    "            durationSeconds: widget.route.durationSeconds,\n"
    "            now: now,\n"
    "          );\n"
    "    final nextScout = scout.asData?.value.nextAfter(journeyProgress);\n"
    "    final points = widget.route.polyline",
    'route scout state',
)
route = replace_once(
    route,
    "    final destination = ChinaCoordinateConverter.wgs84ToGcj02(\n"
    "      widget.destination.point,\n"
    "    );\n"
    "    WidgetsBinding.instance.addPostFrameCallback((_) {",
    "    final destination = ChinaCoordinateConverter.wgs84ToGcj02(\n"
    "      widget.destination.point,\n"
    "    );\n"
    "    final scoutMarkers = <Marker>{};\n"
    "    for (final node in scout.asData?.value.nodes ?? const <RouteScoutNode>[]) {\n"
    "      final place = node.place;\n"
    "      if (place == null || scoutMarkers.length >= 6) continue;\n"
    "      final point = ChinaCoordinateConverter.wgs84ToGcj02(place.point);\n"
    "      scoutMarkers.add(\n"
    "        Marker(\n"
    "          position: LatLng(point.latitude, point.longitude),\n"
    "          infoWindow: InfoWindow(title: place.name),\n"
    "        ),\n"
    "      );\n"
    "    }\n"
    "    WidgetsBinding.instance.addPostFrameCallback((_) {",
    'route scout markers',
)
route = replace_once(
    route,
    "          markers: {\n"
    "            Marker(\n"
    "              position: LatLng(destination.latitude, destination.longitude),\n"
    "              infoWindow: InfoWindow(title: widget.destination.name),\n"
    "            ),\n"
    "          },",
    "          markers: {\n"
    "            Marker(\n"
    "              position: LatLng(destination.latitude, destination.longitude),\n"
    "              infoWindow: InfoWindow(title: widget.destination.name),\n"
    "            ),\n"
    "            ...scoutMarkers,\n"
    "          },",
    'route marker set',
)
route = replace_once(
    route,
    "            snapshot: snapshot,\n"
    "            quiet: quietMode,",
    "            snapshot: snapshot,\n"
    "            scout: scout.asData?.value,\n"
    "            quiet: quietMode,",
    'route verdict scout',
)
route = replace_once(
    route,
    "          height: quietMode ? 150 : 246,\n"
    "          child: _V2RouteActionObject(\n"
    "            route: widget.route,\n"
    "            quiet: quietMode,\n"
    "            active: active,\n"
    "            nextInstruction: widget.route.instructions.firstOrNull,\n"
    "            onStart: _start,\n"
    "            onEnd: _end,\n"
    "            onExplore: () => context.go('/explore'),\n"
    "          ),",
    "          height: quietMode ? 194 : 286,\n"
    "          child: _V2RouteActionObject(\n"
    "            route: widget.route,\n"
    "            scout: scout,\n"
    "            nextScout: nextScout,\n"
    "            quiet: quietMode,\n"
    "            active: active,\n"
    "            nextInstruction: widget.route.instructions.firstOrNull,\n"
    "            onStart: _start,\n"
    "            onEnd: _end,\n"
    "            onScout: _openScout,\n"
    "            onNavigate: () => unawaited(_navigate()),\n"
    "            onExplore: () => context.go('/explore'),\n"
    "          ),",
    'route action object',
)
route = replace_once(
    route,
    "  void _syncPlannedRoute() {",
    "  RouteScoutRequest get _scoutRequest => RouteScoutRequest(\n"
    "    route: widget.route,\n"
    "    destination: widget.destination,\n"
    "    routeKey: _routeKey,\n"
    "  );\n\n"
    "  void _openScout() {\n"
    "    showModalBottomSheet<void>(\n"
    "      context: context,\n"
    "      isScrollControlled: true,\n"
    "      backgroundColor: Colors.transparent,\n"
    "      builder: (sheetContext) => FractionallySizedBox(\n"
    "        heightFactor: .86,\n"
    "        child: _V2RouteScoutSheet(\n"
    "          request: _scoutRequest,\n"
    "          onNavigate: () {\n"
    "            Navigator.of(sheetContext).pop();\n"
    "            unawaited(_navigate());\n"
    "          },\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "  }\n\n"
    "  Future<void> _navigate() async {\n"
    "    final opened = await RouteNavigationLauncher.open(widget.destination);\n"
    "    if (!opened && mounted) {\n"
    "      ScaffoldMessenger.of(context).showSnackBar(\n"
    "        const SnackBar(content: Text('暂时无法打开外部地图')),\n"
    "      );\n"
    "    }\n"
    "  }\n\n"
    "  void _syncPlannedRoute() {",
    'route methods',
)
route = replace_once(
    route,
    "    required this.snapshot,\n"
    "    required this.quiet,",
    "    required this.snapshot,\n"
    "    required this.scout,\n"
    "    required this.quiet,",
    'verdict constructor',
)
route = replace_once(
    route,
    "  final ContextSnapshot? snapshot;\n"
    "  final bool quiet;",
    "  final ContextSnapshot? snapshot;\n"
    "  final RouteScoutPlan? scout;\n"
    "  final bool quiet;",
    'verdict fields',
)
route = replace_once(
    route,
    "    final headline = quiet\n"
    "        ? '路线进行中'\n"
    "        : session == null\n"
    "        ? '路线已经准备好'\n"
    "        : canCatch\n"
    "        ? '按当前路线赶得上'\n"
    "        : '按当前路线已经赶不上';",
    "    final headline = quiet\n"
    "        ? '路线进行中'\n"
    "        : scout?.headline ??\n"
    "              (session == null\n"
    "                  ? '路线已经准备好'\n"
    "                  : canCatch\n"
    "                  ? '按当前路线赶得上'\n"
    "                  : '按当前路线已经赶不上');\n"
    "    final urgent = scout?.criticalCount case final count? when count > 0\n"
    "        ? true\n"
    "        : !canCatch;",
    'verdict headline',
)
route = replace_once(
    route,
    "                color: quiet\n"
    "                    ? V2Palette.moss\n"
    "                    : canCatch\n"
    "                    ? V2Palette.moss\n"
    "                    : V2Palette.ember,",
    "                color: quiet\n"
    "                    ? V2Palette.moss\n"
    "                    : urgent\n"
    "                    ? V2Palette.ember\n"
    "                    : V2Palette.moss,",
    'verdict status color',
)

tail_start = route.index('class _V2RouteActionObject extends StatelessWidget {')
route_tail = r'''class _V2RouteActionObject extends StatelessWidget {
  const _V2RouteActionObject({
    required this.route,
    required this.scout,
    required this.nextScout,
    required this.quiet,
    required this.active,
    required this.nextInstruction,
    required this.onStart,
    required this.onEnd,
    required this.onScout,
    required this.onNavigate,
    required this.onExplore,
  });

  final DrivingRoute route;
  final AsyncValue<RouteScoutPlan> scout;
  final RouteScoutNode? nextScout;
  final bool quiet;
  final bool active;
  final String? nextInstruction;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onScout;
  final VoidCallback onNavigate;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final plan = scout.asData?.value;
    final headline = quiet
        ? (nextScout?.title ?? nextInstruction ?? '沿路线继续前行')
        : plan?.headline ??
              (scout.isLoading ? '正在整理沿途信息' : '路线已准备好');
    final detail = quiet
        ? nextScout?.detail
        : plan == null
        ? '探路失败不会影响路线与外部导航。'
        : '${plan.criticalCount + plan.highCount} 条重点 · '
              '${plan.photographyCount} 个拍摄时间 · ${plan.supportCount} 个补给线索';
    return Material(
      color: quiet ? V2Palette.night : V2Palette.paper,
      elevation: 18,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, quiet ? 18 : 22, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  quiet ? '下一条重要节点' : '路线探路',
                  style: TextStyle(
                    color: quiet ? V2Palette.moss : V2Palette.moss,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (plan != null)
                  Text(
                    plan.coverage == RouteScoutCoverage.full ? '数据完整' : '部分数据',
                    style: TextStyle(
                      color: quiet ? Colors.white54 : V2Palette.mutedInk,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              headline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: quiet ? Colors.white : V2Palette.ink,
                fontSize: quiet ? 19 : 22,
                height: 1.15,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 7),
              Text(
                detail,
                maxLines: quiet ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: quiet ? Colors.white60 : V2Palette.mutedInk,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                V2RoundAction(
                  icon: CupertinoIcons.map,
                  label: '探路',
                  onTap: onScout,
                ),
                const SizedBox(width: 10),
                V2RoundAction(
                  icon: quiet
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.arrow_2_circlepath,
                  label: quiet ? '导航' : '换地点',
                  onTap: quiet ? onNavigate : onExplore,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: V2Pressable(
                    onTap: active ? onEnd : onStart,
                    color: quiet ? V2Palette.paper : V2Palette.moss,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Text(
                        active ? '结束行程' : '开始行程',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: quiet ? V2Palette.ink : Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _V2RouteScoutSheet extends ConsumerWidget {
  const _V2RouteScoutSheet({
    required this.request,
    required this.onNavigate,
  });

  final RouteScoutRequest request;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scout = ref.watch(routeScoutPlanProvider(request));
    return Material(
      color: V2Palette.canvas,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: V2Palette.mutedInk.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '路线探路',
                          style: TextStyle(
                            color: V2Palette.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.7,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '只展示会影响行动的沿途信息，不替代地图导航。',
                          style: TextStyle(
                            color: V2Palette.mutedInk,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
            ),
            Expanded(
              child: scout.when(
                loading: () => const Center(
                  child: V2LoadingObject(label: '正在读取沿途天气与补给'),
                ),
                error: (_, _) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      '探路数据暂时不可用，路线和外部导航仍可正常使用。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: V2Palette.mutedInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                data: (plan) => _V2RouteScoutTimeline(plan: plan),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: V2Pressable(
                onTap: onNavigate,
                color: V2Palette.moss,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.location_fill, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        '打开高德地图导航',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _V2RouteScoutTimeline extends StatelessWidget {
  const _V2RouteScoutTimeline({required this.plan});

  final RouteScoutPlan plan;

  @override
  Widget build(BuildContext context) {
    if (plan.nodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            '沿途暂无需要额外打断行程的信息。',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: plan.nodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final node = plan.nodes[index];
        return Material(
          color: V2Palette.paper,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _nodeColor(node).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _nodeIcon(node.kind),
                    color: _nodeColor(node),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              node.title,
                              style: const TextStyle(
                                color: V2Palette.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(node.routeProgress * 100).round()}% · ${_time(node.expectedAt)}',
                            style: const TextStyle(
                              color: V2Palette.mutedInk,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        node.detail,
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${node.source}${node.isStale ? ' · 缓存' : ''}',
                        style: TextStyle(
                          color: _nodeColor(node).withValues(alpha: .8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static Color _nodeColor(RouteScoutNode node) => switch (node.priority) {
    RouteScoutPriority.critical => V2Palette.ember,
    RouteScoutPriority.high => V2Palette.ember,
    RouteScoutPriority.normal => V2Palette.moss,
  };

  static IconData _nodeIcon(RouteScoutNodeKind kind) => switch (kind) {
    RouteScoutNodeKind.safety => Icons.warning_amber_rounded,
    RouteScoutNodeKind.weather => Icons.cloud_outlined,
    RouteScoutNodeKind.photography => Icons.photo_camera_outlined,
    RouteScoutNodeKind.fuel => Icons.local_gas_station_outlined,
    RouteScoutNodeKind.supply => Icons.shopping_bag_outlined,
    RouteScoutNodeKind.food => Icons.restaurant_outlined,
    RouteScoutNodeKind.parking => Icons.local_parking_outlined,
    RouteScoutNodeKind.medical => Icons.medical_services_outlined,
    RouteScoutNodeKind.route => Icons.route_outlined,
  };
}
'''
route = route[:tail_start] + route_tail
route_path.write_text(route)

context_path = Path('services/lumanest-data-broker/src/assistant/context-envelope.mjs')
context = context_path.read_text()
context = replace_once(
    context,
    "const regionBriefSections = Object.freeze([",
    "import {\n"
    "  coarseRouteCorridor,\n"
    "  routeWeatherFacts,\n"
    "  validRouteCorridorBinding,\n"
    "} from './route-scout-context.mjs';\n\n"
    "const regionBriefSections = Object.freeze([",
    'context import',
)
context = replace_once(
    context,
    "    sceneProfile: Object.freeze({",
    "    routeCorridor: coarseRouteCorridor(route),\n"
    "    sceneProfile: Object.freeze({",
    'context route binding',
)
context = replace_once(
    context,
    "    value.region.radiusMeters <= 50_000 && typeof value.locale === 'string';",
    "    value.region.radiusMeters <= 50_000 && typeof value.locale === 'string' &&\n"
    "    validRouteCorridorBinding(value.routeCorridor);",
    'context binding validation',
)
context = replace_once(
    context,
    "  loadRegionBrief,\n"
    "  now = new Date(),",
    "  loadRegionBrief,\n"
    "  loadRouteWeather,\n"
    "  now = new Date(),",
    'context function signature',
)
context = replace_once(
    context,
    "  const [providerBundle, regionResult] = await Promise.all([\n"
    "    settleWithin(providerTask, timeoutMs),\n"
    "    settleWithin(regionTask, timeoutMs),\n"
    "  ]);",
    "  const routeTask = typeof loadRouteWeather === 'function' && binding.routeCorridor != null\n"
    "    ? Promise.resolve().then(() => loadRouteWeather({\n"
    "        routeId: binding.routeCorridor.routeId,\n"
    "        samples: binding.routeCorridor.samples,\n"
    "      }))\n"
    "    : null;\n"
    "  const [providerBundle, regionResult, routeResult] = await Promise.all([\n"
    "    settleWithin(providerTask, timeoutMs),\n"
    "    settleWithin(regionTask, timeoutMs),\n"
    "    settleWithin(routeTask, timeoutMs),\n"
    "  ]);",
    'context route task',
)
context = replace_once(
    context,
    "  const providers = providerFacts(providerBundle, now);\n"
    "  const contextFacts = [...baseLines, ...region.lines, ...providers.lines]",
    "  const providers = providerFacts(providerBundle, now);\n"
    "  const route = routeWeatherFacts(routeResult, now);\n"
    "  const contextFacts = [...baseLines, ...route.lines, ...region.lines, ...providers.lines]",
    'context route facts',
)
context = replace_once(
    context,
    "    factIds: Object.freeze([...new Set([...region.factIds, ...providers.factIds])].slice(0, 12)),",
    "    factIds: Object.freeze([\n"
    "      ...new Set([...route.factIds, ...region.factIds, ...providers.factIds]),\n"
    "    ].slice(0, 12)),",
    'context route fact ids',
)
context = replace_once(
    context,
    "      [snapshot.expiresAt, region.expiresAt, providers.expiresAt],",
    "      [snapshot.expiresAt, route.expiresAt, region.expiresAt, providers.expiresAt],",
    'context route expiry',
)
context_path.write_text(context)

server_path = Path('services/lumanest-data-broker/src/server.mjs')
server = server_path.read_text()
server = replace_once(
    server,
    "            loadRegionBrief: (regionBody) => forwardRegionBrief({\n"
    "              body: regionBody,\n"
    "              serviceUrl: configuration.discoveryServiceUrl,\n"
    "              internalToken: configuration.discoveryInternalToken,\n"
    "              sourcePolicies: configuration.discoverySearchProfile.sourcePolicies,\n"
    "              fetcher,\n"
    "              timeoutMs: Math.min(configuration.settings.upstreamTimeoutMs, 2_000),\n"
    "            }),\n"
    "            now: assistantNow,",
    "            loadRegionBrief: (regionBody) => forwardRegionBrief({\n"
    "              body: regionBody,\n"
    "              serviceUrl: configuration.discoveryServiceUrl,\n"
    "              internalToken: configuration.discoveryInternalToken,\n"
    "              sourcePolicies: configuration.discoverySearchProfile.sourcePolicies,\n"
    "              fetcher,\n"
    "              timeoutMs: Math.min(configuration.settings.upstreamTimeoutMs, 2_000),\n"
    "            }),\n"
    "            loadRouteWeather: (routeBody) => routeWeatherForecast({\n"
    "              body: routeBody,\n"
    "              now: () => assistantNow,\n"
    "              fetchWeather: (coordinate) => authoritativeWeather({\n"
    "                coordinate,\n"
    "                apiHost: configuration.qweatherApiHost,\n"
    "                privateKey: configuration.privateKey,\n"
    "                keyId: configuration.keyId,\n"
    "                projectId: configuration.projectId,\n"
    "                cache: weatherCache,\n"
    "                fetcher,\n"
    "                now,\n"
    "                timeoutMs: configuration.settings.upstreamTimeoutMs,\n"
    "              }),\n"
    "            }),\n"
    "            now: assistantNow,",
    'server assistant route weather',
)
server_path.write_text(server)

# Fix num-returning clamp expressions in the newly added Dart model.
plan_path = Path('lib/src/features/route/domain/route_scout_plan.dart')
plan = plan_path.read_text()
plan = plan.replace(
    "    final floor = (progress - .03).clamp(0.0, 1.0);",
    "    final floor = (progress - .03).clamp(0.0, 1.0).toDouble();",
)
plan = plan.replace(
    "    return (elapsed / durationSeconds).clamp(0.0, 1.0);",
    "    return (elapsed / durationSeconds).clamp(0.0, 1.0).toDouble();",
)
plan = plan.replace(
    "          : (seconds / durationSeconds).clamp(0.0, 1.0);",
    "          : (seconds / durationSeconds).clamp(0.0, 1.0).toDouble();",
)
plan = plan.replace(
    "      final progress = stop.routeProgress.clamp(0.0, 1.0);",
    "      final progress = stop.routeProgress.clamp(0.0, 1.0).toDouble();",
)
plan_path.write_text(plan)
