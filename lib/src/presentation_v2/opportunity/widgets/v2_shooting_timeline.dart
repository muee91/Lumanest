part of '../v2_opportunity_page.dart';

class _V2Timeline extends StatelessWidget {
  const _V2Timeline({
    required this.phases,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<ShootingSessionPhase> phases;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '拍摄时间轴',
        style: TextStyle(
          color: V2Palette.ink,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 98,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minimumWidth = phases.length * 88.0;
            final contentWidth = minimumWidth > constraints.maxWidth
                ? minimumWidth
                : constraints.maxWidth;
            final lineInset = contentWidth / phases.length / 2;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: 98,
                child: Stack(
                  children: [
                    Positioned(
                      left: lineInset,
                      right: lineInset,
                      top: 11,
                      child: Container(height: 2, color: V2Palette.line),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < phases.length; index++)
                          Expanded(
                            child: _V2PhaseNode(
                              key: Key('v2-phase-node-$index'),
                              phase: phases[index],
                              selected: index == selectedIndex,
                              onTap: () => onSelected(index),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _V2PhaseNode extends StatelessWidget {
  const _V2PhaseNode({
    super.key,
    required this.phase,
    required this.selected,
    required this.onTap,
  });
  final ShootingSessionPhase phase;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${label(phase.kind)}，${_time(phase.startsAt)}',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 24 : 20,
            height: selected ? 24 : 20,
            decoration: BoxDecoration(
              color: _color(phase.conditionBand),
              shape: BoxShape.circle,
              border: Border.all(color: V2Palette.canvas, width: 3),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label(phase.kind),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: V2Palette.ink,
              fontSize: 11,
              height: 1.2,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _time(phase.startsAt),
            style: const TextStyle(color: V2Palette.mutedInk, fontSize: 10),
          ),
        ],
      ),
    ),
  );

  static Color _color(ShootingConditionBand value) => switch (value) {
    ShootingConditionBand.good => V2Palette.moss,
    ShootingConditionBand.fair => V2Palette.ember,
    ShootingConditionBand.limited => V2Palette.line,
  };

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static String label(ShootingPhaseKind value) => switch (value) {
    ShootingPhaseKind.morningBlueHour => '晨间蓝调',
    ShootingPhaseKind.sunrise => '日出',
    ShootingPhaseKind.morningMist => '晨雾',
    ShootingPhaseKind.reflection => '倒影',
    ShootingPhaseKind.warmLight => '暖光',
    ShootingPhaseKind.sunset => '日落',
    ShootingPhaseKind.blueHour => '蓝调',
    ShootingPhaseKind.artificialLights => '灯光',
    ShootingPhaseKind.rainEnding => '雨停',
    ShootingPhaseKind.wetReflection => '湿地反光',
    ShootingPhaseKind.desertSideLight => '侧光',
    ShootingPhaseKind.texture => '纹理',
    ShootingPhaseKind.approach => '接近',
    ShootingPhaseKind.safeStop => '安全停车',
    ShootingPhaseKind.shoot => '拍摄',
    ShootingPhaseKind.rejoinRoute => '返回路线',
    ShootingPhaseKind.returnWindow => '返程窗口',
    ShootingPhaseKind.sessionEnd => '结束',
  };
}
