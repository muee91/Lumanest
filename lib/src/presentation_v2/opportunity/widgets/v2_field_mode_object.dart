part of '../v2_opportunity_page.dart';

class _V2FieldFact {
  const _V2FieldFact({required this.label, required this.value});

  final String label;
  final String value;
}

class _V2FieldModeObject extends StatefulWidget {
  const _V2FieldModeObject({
    required this.atTarget,
    required this.automaticArrival,
    required this.distanceMeters,
    required this.decision,
    required this.target,
    required this.facts,
    required this.dataObservedAt,
    required this.directionDegrees,
    required this.onToggle,
  });

  final bool atTarget;
  final bool automaticArrival;
  final double? distanceMeters;
  final ShootingExecutionDecision decision;
  final ShootingTarget target;
  final List<_V2FieldFact> facts;
  final DateTime? dataObservedAt;
  final double directionDegrees;
  final VoidCallback onToggle;

  @override
  State<_V2FieldModeObject> createState() => _V2FieldModeObjectState();
}

class _V2FieldModeObjectState extends State<_V2FieldModeObject> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _V2FieldModeObject oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.atTarget != widget.atTarget ||
        oldWidget.decision.phase != widget.decision.phase ||
        oldWidget.decision.state != widget.decision.state) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (!widget.atTarget || widget.decision.phase == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final countdown = _countdownLabel();
    final distance = widget.distanceMeters == null
        ? null
        : widget.distanceMeters! < 1000
        ? '${widget.distanceMeters!.round()}m'
        : '${(widget.distanceMeters! / 1000).toStringAsFixed(1)}km';
    return V2Pressable(
      key: const Key('v2-arrived-at-target'),
      onTap: widget.onToggle,
      color: widget.atTarget ? V2Palette.mossSoft : V2Palette.paper,
      semanticLabel: widget.atTarget ? '已到达机位，关闭现场模式' : '已到达机位，进入现场模式',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  widget.atTarget
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.location,
                  color: widget.atTarget ? V2Palette.moss : V2Palette.mutedInk,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.atTarget
                            ? '现场模式 · ${widget.decision.label}'
                            : '到达机位后再判断',
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.atTarget
                            ? '${widget.target.name} · ${_directionArrow(widget.directionDegrees)} ${widget.directionDegrees.round()}° 观察'
                            : distance == null
                            ? '由你确认已经抵达 ${widget.target.name}'
                            : '距 ${widget.target.name} $distance · 到达后进入现场模式',
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  widget.atTarget
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  color: widget.atTarget ? V2Palette.moss : V2Palette.mutedInk,
                ),
              ],
            ),
            if (widget.atTarget && countdown != null) ...[
              const SizedBox(height: 13),
              Text(
                countdown,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
            ],
            if (widget.atTarget && widget.facts.isNotEmpty) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fact in widget.facts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: V2Palette.paper,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: V2Palette.line),
                      ),
                      child: Text(
                        '${fact.label} ${fact.value}',
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (widget.atTarget) ...[
              const SizedBox(height: 10),
              Text(
                <String>[
                  widget.automaticArrival ? '已按前台定位识别到达' : '由你手动确认到达',
                  if (widget.dataObservedAt != null)
                    '环境 ${_time(widget.dataObservedAt!)} 更新',
                ].join(' · '),
                style: const TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _countdownLabel() {
    final phase = widget.decision.phase;
    if (phase == null) return null;
    final now = DateTime.now();
    final target = widget.decision.state == ShootingExecutionState.shootNow
        ? phase.endsAt
        : phase.startsAt;
    final remaining = target.difference(now);
    if (remaining <= Duration.zero) return null;
    final prefix = widget.decision.state == ShootingExecutionState.shootNow
        ? '${_V2PhaseNode.label(phase.kind)}还剩'
        : '距${_V2PhaseNode.label(phase.kind)}';
    return '$prefix ${_duration(remaining)}';
  }

  static String _duration(Duration value) {
    final seconds = value.inSeconds;
    if (value > const Duration(minutes: 10)) {
      final totalMinutes = (seconds / 60).ceil();
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      return hours == 0
          ? '$totalMinutes 分钟'
          : minutes == 0
          ? '$hours 小时'
          : '$hours 小时 $minutes 分钟';
    }
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  static String _directionArrow(double degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    if (normalized < 22.5 || normalized >= 337.5) return '↑';
    if (normalized < 67.5) return '↗';
    if (normalized < 112.5) return '→';
    if (normalized < 157.5) return '↘';
    if (normalized < 202.5) return '↓';
    if (normalized < 247.5) return '↙';
    if (normalized < 292.5) return '←';
    return '↖';
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
