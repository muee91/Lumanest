part of '../v2_route_page.dart';

class _V2RouteActionObject extends StatelessWidget {
  const _V2RouteActionObject({
    required this.scout,
    required this.onScout,
    required this.onNavigate,
    required this.onExplore,
  });

  final AsyncValue<RouteScoutPlan> scout;
  final VoidCallback onScout;
  final VoidCallback onNavigate;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    final plan = scout.asData?.value;
    final blocking = plan?.hasBlockingSafety ?? false;
    final headline =
        plan?.headline ?? (scout.isLoading ? '正在整理沿途信息' : '路线已准备好');
    final detail = plan == null
        ? '探路失败不会影响路线与外部导航。'
        : '${plan.criticalCount + plan.highCount} 条重点 · '
              '${plan.photographyCount} 个拍摄时间 · ${plan.supportCount} 个补给线索';
    return Material(
      color: V2Palette.paper,
      elevation: 18,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '路线探路',
                  style: TextStyle(
                    color: V2Palette.moss,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (plan != null)
                  Text(
                    plan.coverage == RouteScoutCoverage.full ? '数据完整' : '部分数据',
                    style: const TextStyle(
                      color: V2Palette.mutedInk,
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
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w900,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (blocking) ...[
                  Expanded(
                    child: V2Pressable(
                      onTap: onScout,
                      color: V2Palette.ember,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 15),
                        child: Text(
                          '查看管制',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  V2RoundAction(
                    icon: CupertinoIcons.map,
                    label: '导航',
                    onTap: onNavigate,
                  ),
                ] else ...[
                  V2RoundAction(
                    icon: CupertinoIcons.map,
                    label: '探路',
                    onTap: onScout,
                  ),
                  const SizedBox(width: 10),
                  V2RoundAction(
                    icon: CupertinoIcons.arrow_2_circlepath,
                    label: '换地点',
                    onTap: onExplore,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: V2Pressable(
                      onTap: onNavigate,
                      color: V2Palette.moss,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 15),
                        child: Text(
                          '打开导航',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
