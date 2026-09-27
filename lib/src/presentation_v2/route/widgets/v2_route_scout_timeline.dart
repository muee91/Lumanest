part of '../v2_route_page.dart';

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

  static Color _nodeColor(RouteScoutNode node) => switch (node.actionSeverity) {
    RouteScoutActionSeverity.blocking ||
    RouteScoutActionSeverity.urgent ||
    RouteScoutActionSeverity.advisory => V2Palette.ember,
    RouteScoutActionSeverity.normal => V2Palette.moss,
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
