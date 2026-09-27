part of '../v2_opportunity_page.dart';

class _V2PlanBObject extends StatelessWidget {
  const _V2PlanBObject({
    required this.primary,
    required this.alternative,
    required this.onOpen,
  });

  final ShootingSession primary;
  final ShootingSession alternative;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => V2Pressable(
    key: const Key('v2-opportunity-plan-b'),
    onTap: onOpen,
    color: V2Palette.paper,
    semanticLabel: '查看备选拍摄机会 ${alternative.title}',
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.arrow_right,
            color: V2Palette.ember,
            size: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '条件变化 · 有备选',
                  style: TextStyle(
                    color: V2Palette.ember,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alternative.title,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${primary.title}正在减弱；这个窗口仍有已成立依据。',
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_right,
            color: V2Palette.mutedInk,
            size: 17,
          ),
        ],
      ),
    ),
  );
}
