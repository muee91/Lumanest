part of '../v2_route_page.dart';

class _V2RouteScoutSheet extends ConsumerWidget {
  const _V2RouteScoutSheet({required this.request, required this.onNavigate});

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
                loading: () =>
                    const Center(child: V2LoadingObject(label: '正在读取沿途天气与补给')),
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
