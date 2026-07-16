import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../domain/inspiration_bottle_layout.dart';
import '../../domain/inspiration_note.dart';

/// Tactile presentation for creative notes. It has no route or safety logic.
class InspirationBottle extends StatefulWidget {
  const InspirationBottle({
    super.key,
    required this.snapshotId,
    required this.notes,
    required this.selectedId,
    required this.reduceMotion,
    required this.enableShake,
    required this.onDraw,
    required this.onSelect,
  });

  final String snapshotId;
  final List<InspirationNote> notes;
  final String selectedId;
  final bool reduceMotion;
  final bool enableShake;
  final VoidCallback onDraw;
  final ValueChanged<InspirationNote> onSelect;

  @override
  State<InspirationBottle> createState() => _InspirationBottleState();
}

class _InspirationBottleState extends State<InspirationBottle>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _paperWidth = 72.0;
  static const _paperHeight = 45.0;
  static const _interiorWidth = 250.0;
  static const _interiorHeight = 292.0;
  late final AnimationController _idleController;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastShake;
  String? _draggedNoteId;
  Offset _dragOffset = Offset.zero;
  bool _entered = false;
  bool _tickerVisible = true;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    _syncMotion();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _entered = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible != _tickerVisible) {
      _tickerVisible = visible;
      _syncMotion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _appResumed) return;
    _appResumed = resumed;
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant InspirationBottle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion ||
        oldWidget.enableShake != widget.enableShake) {
      _syncMotion();
    }
  }

  void _syncMotion() {
    final foreground = _tickerVisible && _appResumed;
    final allowMotion = !widget.reduceMotion && foreground;
    if (allowMotion) {
      if (!_idleController.isAnimating) _idleController.repeat();
    } else {
      _idleController
        ..stop()
        ..value = 0;
    }
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    if (!widget.enableShake || widget.reduceMotion || !foreground) return;
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 80),
    ).listen(_onAcceleration, onError: (_) {});
  }

  void _onAcceleration(AccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (magnitude < 18) return;
    final now = DateTime.now();
    if (_lastShake != null &&
        now.difference(_lastShake!).inMilliseconds < 900) {
      return;
    }
    _lastShake = now;
    widget.onDraw();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelerometerSubscription?.cancel();
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layouts = InspirationBottleLayout.build(
      snapshotId: widget.snapshotId,
      notes: widget.notes,
    );
    final notes = {for (final note in widget.notes) note.id: note};
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '灵感瓶，双击抽取纸条；也可以拖动瓶内纸条',
      child: GestureDetector(
        key: const Key('inspiration-bottle'),
        onTap: widget.onDraw,
        child: AnimatedBuilder(
          animation: _idleController,
          builder: (context, _) {
            final sway = widget.reduceMotion
                ? 0.0
                : math.sin(_idleController.value * math.pi * 2) * .012;
            return Transform.rotate(
              angle: sway,
              child: SizedBox(
                width: 292,
                height: 382,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      top: 0,
                      child: _BottleNeck(color: theme.colorScheme.primary),
                    ),
                    Positioned(
                      top: 48,
                      child: _BottleBody(
                        child: Stack(
                          children: [
                            for (final layout in layouts)
                              if (notes[layout.id] case final note?)
                                _BottlePaper(
                                  note: note,
                                  layout: layout,
                                  entered: _entered,
                                  selected: note.id == widget.selectedId,
                                  dragged: note.id == _draggedNoteId,
                                  dragOffset: note.id == _draggedNoteId
                                      ? _dragOffset
                                      : Offset.zero,
                                  onTap: () => widget.onSelect(note),
                                  onPanStart: () => setState(() {
                                    _draggedNoteId = note.id;
                                    _dragOffset = Offset.zero;
                                  }),
                                  onPanUpdate: (details) => setState(() {
                                    _dragOffset += details.delta;
                                  }),
                                  onPanEnd: (_) {
                                    widget.onSelect(note);
                                    setState(() {
                                      _draggedNoteId = null;
                                      _dragOffset = Offset.zero;
                                    });
                                  },
                                ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BottleNeck extends StatelessWidget {
  const _BottleNeck({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    height: 78,
    child: Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          width: 84,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .20),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: Colors.white.withValues(alpha: .54),
              width: 1.4,
            ),
          ),
        ),
        Positioned(
          top: 17,
          child: Container(
            width: 106,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .74),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ],
    ),
  );
}

class _BottleBody extends StatelessWidget {
  const _BottleBody({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 250,
    height: 306,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(54),
        bottom: Radius.circular(84),
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFAED1DE).withValues(alpha: .46),
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .34),
          const Color(0xFFF3E9D9).withValues(alpha: .22),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: .72),
        width: 1.6,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .10),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          left: 18,
          top: 24,
          bottom: 48,
          child: Container(
            width: 9,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .36),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    ),
  );
}

class _BottlePaper extends StatelessWidget {
  const _BottlePaper({
    required this.note,
    required this.layout,
    required this.entered,
    required this.selected,
    required this.dragged,
    required this.dragOffset,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final InspirationNote note;
  final BottlePaperLayout layout;
  final bool entered;
  final bool selected;
  final bool dragged;
  final Offset dragOffset;
  final VoidCallback onTap;
  final VoidCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) => AnimatedPositioned(
    duration: const Duration(milliseconds: 520),
    curve: Curves.easeOutBack,
    left: layout.leftFraction * _InspirationBottleState._interiorWidth,
    top: entered
        ? layout.topFraction * _InspirationBottleState._interiorHeight
        : -_InspirationBottleState._paperHeight,
    child: Transform.translate(
      offset: dragOffset,
      child: Transform.rotate(
        angle: layout.rotation + (dragged ? .08 : 0),
        child: GestureDetector(
          onTap: onTap,
          onPanStart: (_) => onPanStart(),
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            scale: selected || dragged ? 1.07 : 1,
            child: Container(
              key: Key('bottle-paper-${note.id}'),
              width: _InspirationBottleState._paperWidth,
              height: _InspirationBottleState._paperHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFF3E9D9,
                ).withValues(alpha: selected ? .98 : .78),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: const Color(0xFF806C55).withValues(alpha: .26),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: selected ? .18 : .08),
                    blurRadius: selected ? 10 : 4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                note.displayLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF3B3832),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
