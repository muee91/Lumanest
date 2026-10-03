part of '../v2_opportunity_page.dart';

class _V2ShootingAdvice extends StatelessWidget {
  const _V2ShootingAdvice({
    required this.phase,
    required this.capabilities,
    required this.target,
  });

  final ShootingSessionPhase phase;
  final Set<EquipmentCapability> capabilities;
  final ShootingTarget? target;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '拍摄建议',
        style: TextStyle(
          color: context.v2Ink,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.v2Paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.v2Line),
        ),
        child: Column(
          children: [
            _V2AdviceRow(
              label: '重点阶段',
              value:
                  '${_V2PhaseNode.label(phase.kind)} · ${_time(phase.startsAt)}—${_time(phase.endsAt)}',
            ),
            const SizedBox(height: 12),
            _V2AdviceRow(
              label: '观察方向',
              value: '${phase.directionDegrees.round()}°',
            ),
            if (target != null) ...[
              const SizedBox(height: 12),
              _V2AdviceRow(label: '审核机位', value: target!.name),
            ],
            if (capabilities.isNotEmpty) ...[
              const SizedBox(height: 12),
              _V2AdviceRow(
                label: '可用器材',
                value: capabilities.map(_capabilityLabel).join('、'),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  static String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:'
      '${value.toLocal().minute.toString().padLeft(2, '0')}';

  static String _capabilityLabel(EquipmentCapability value) => switch (value) {
    EquipmentCapability.camera => '相机',
    EquipmentCapability.phoneCamera => '手机',
    EquipmentCapability.tripod => '三脚架',
    EquipmentCapability.wideAngle => '广角',
    EquipmentCapability.telephoto => '长焦',
    EquipmentCapability.fastLens => '大光圈',
    EquipmentCapability.filter => '滤镜',
    EquipmentCapability.drone => '无人机',
    EquipmentCapability.weatherProtection => '防雨',
    EquipmentCapability.headlamp => '照明',
  };
}

class _V2AdviceRow extends StatelessWidget {
  const _V2AdviceRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: TextStyle(
            color: context.v2MutedInk,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: context.v2Ink,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}
