part of '../v2_opportunity_page.dart';

class _V2EvidenceToggle extends StatelessWidget {
  const _V2EvidenceToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    key: const Key('v2-evidence-toggle'),
    onTap: onTap,
    compact: true,
    color: context.v2Paper,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.checkmark_shield,
            color: context.v2Moss,
            size: 18,
          ),
          const SizedBox(width: 9),
          Text(
            open ? '收起判断依据' : '查看判断依据',
            style: TextStyle(color: context.v2Ink, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Icon(
            open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
            color: context.v2MutedInk,
            size: 16,
          ),
        ],
      ),
    ),
  );
}

class _V2FactorObject extends StatelessWidget {
  const _V2FactorObject({required this.factor});
  final ShootingSessionFactor factor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: switch (factor.effect) {
        ShootingFactorEffect.supporting => context.v2MossSoft,
        ShootingFactorEffect.neutral => context.v2Paper,
        ShootingFactorEffect.limiting => context.v2EmberSoft,
      },
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.v2Line),
    ),
    child: Text(
      '${factor.label} ${factor.value}',
      style: TextStyle(
        color: context.v2Ink,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _V2TargetObject extends StatelessWidget {
  const _V2TargetObject({required this.target});
  final ShootingTarget? target;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: target == null ? context.v2Canvas : context.v2SkySoft,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.v2Line),
    ),
    child: Row(
      children: [
        Icon(
          target == null ? CupertinoIcons.location_slash : CupertinoIcons.scope,
          color: target == null ? context.v2MutedInk : context.v2Sky,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target?.name ?? '暂无经过审核的推荐机位',
                style: TextStyle(
                  color: context.v2Ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                target == null ? '只展示时间与条件，不绑定最近 POI。' : '方向、到场提前量与来源已通过审核。',
                style: TextStyle(color: context.v2MutedInk, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
