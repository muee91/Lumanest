import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/design/luma_nest_motion.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

/// A single moving selection object plus one isolated creation action.
///
/// The hierarchy follows the live calLog reference: frequent destinations
/// share one quiet material capsule, while the creation action remains a
/// separate circular object. Labels stay in semantics instead of chrome.
class V2ObjectNavigationDock extends StatefulWidget {
  const V2ObjectNavigationDock({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.reduceMotion,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final bool reduceMotion;

  @override
  State<V2ObjectNavigationDock> createState() => _V2ObjectNavigationDockState();
}

class _V2ObjectNavigationDockState extends State<V2ObjectNavigationDock> {
  static const _primaryItems = <_V2DockItem>[
    _V2DockItem(
      branchIndex: 0,
      label: '今日',
      icon: CupertinoIcons.sun_max,
      selectedIcon: CupertinoIcons.sun_max_fill,
    ),
    _V2DockItem(
      branchIndex: 1,
      label: '探索',
      icon: CupertinoIcons.compass,
      selectedIcon: CupertinoIcons.compass_fill,
    ),
    _V2DockItem(
      branchIndex: 2,
      label: '路线',
      icon: CupertinoIcons.map,
      selectedIcon: CupertinoIcons.map_fill,
    ),
    _V2DockItem(
      branchIndex: 4,
      label: '我的',
      icon: CupertinoIcons.person_crop_circle,
      selectedIcon: CupertinoIcons.person_crop_circle_fill,
    ),
  ];

  static const _inspiration = _V2DockItem(
    branchIndex: 3,
    label: '灵感',
    icon: CupertinoIcons.sparkles,
    selectedIcon: CupertinoIcons.sparkles,
  );

  late int _displayedSlot;

  int? get _selectedSlot {
    final slot = _primaryItems.indexWhere(
      (item) => item.branchIndex == widget.currentIndex,
    );
    return slot < 0 ? null : slot;
  }

  @override
  void initState() {
    super.initState();
    _displayedSlot = _selectedSlot ?? 0;
  }

  @override
  void didUpdateWidget(covariant V2ObjectNavigationDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedSlot = _selectedSlot;
    if (selectedSlot != null) _displayedSlot = selectedSlot;
  }

  Duration get _moveDuration =>
      widget.reduceMotion ? Duration.zero : LumaNestMotion.containerTransform;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: SizedBox(
      key: const Key('v2-bottom-navigation'),
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildPrimaryRail()),
          const SizedBox(width: 10),
          _V2DockButton(
            key: const Key('v2-inspiration-navigation-action'),
            item: _inspiration,
            selected: widget.currentIndex == _inspiration.branchIndex,
            isolated: true,
            reduceMotion: widget.reduceMotion,
            onTap: () => widget.onSelected(_inspiration.branchIndex),
          ),
        ],
      ),
    ),
  );

  Widget _buildPrimaryRail() => ClipRRect(
    key: const Key('v2-object-navigation-rail'),
    borderRadius: BorderRadius.circular(32),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xEAF1F1EE),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: .86)),
          boxShadow: [
            BoxShadow(
              color: V2Palette.ink.withValues(alpha: .13),
              blurRadius: 24,
              offset: const Offset(0, 11),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotWidth = constraints.maxWidth / _primaryItems.length;
            return Stack(
              fit: StackFit.expand,
              children: [
                AnimatedPositioned(
                  duration: _moveDuration,
                  curve: Curves.easeOutBack,
                  left: slotWidth * _displayedSlot + 4,
                  top: 4,
                  width: slotWidth - 8,
                  bottom: 4,
                  child: AnimatedOpacity(
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : LumaNestMotion.contentEnter,
                    opacity: _selectedSlot == null ? 0 : 1,
                    child: _V2MovingSelectionLens(
                      slot: _displayedSlot,
                      reduceMotion: widget.reduceMotion,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final item in _primaryItems)
                      Expanded(
                        child: _V2DockButton(
                          item: item,
                          selected: item.branchIndex == widget.currentIndex,
                          reduceMotion: widget.reduceMotion,
                          onTap: () => widget.onSelected(item.branchIndex),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _V2DockItem {
  const _V2DockItem({
    required this.branchIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final int branchIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _V2MovingSelectionLens extends StatefulWidget {
  const _V2MovingSelectionLens({
    required this.slot,
    required this.reduceMotion,
  });

  final int slot;
  final bool reduceMotion;

  @override
  State<_V2MovingSelectionLens> createState() => _V2MovingSelectionLensState();
}

class _V2MovingSelectionLensState extends State<_V2MovingSelectionLens>
    with SingleTickerProviderStateMixin {
  late final AnimationController _squish;

  @override
  void initState() {
    super.initState();
    _squish = AnimationController(
      vsync: this,
      duration: LumaNestMotion.containerTransform,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _V2MovingSelectionLens oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot != widget.slot && !widget.reduceMotion) {
      _squish.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _squish.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _squish,
    builder: (context, child) {
      final pulse = math.sin(_squish.value * math.pi);
      return Transform.scale(
        scaleX: 1 + pulse * .13,
        scaleY: 1 - pulse * .06,
        child: child,
      );
    },
    child: DecoratedBox(
      key: const Key('v2-moving-selection-lens'),
      decoration: BoxDecoration(
        color: V2Palette.mossSoft.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: Colors.white.withValues(alpha: .78)),
        boxShadow: [
          BoxShadow(
            color: V2Palette.moss.withValues(alpha: .18),
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: .78),
            blurRadius: 7,
            offset: const Offset(0, -2),
          ),
        ],
      ),
    ),
  );
}

class _V2DockButton extends StatefulWidget {
  const _V2DockButton({
    super.key,
    required this.item,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
    this.isolated = false,
  });

  final _V2DockItem item;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;
  final bool isolated;

  @override
  State<_V2DockButton> createState() => _V2DockButtonState();
}

class _V2DockButtonState extends State<_V2DockButton> {
  bool _pressed = false;

  Duration get _duration =>
      widget.reduceMotion ? Duration.zero : LumaNestMotion.contentEnter;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    selected: widget.selected,
    label: widget.item.label,
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: widget.reduceMotion
              ? Duration.zero
              : _pressed
              ? LumaNestMotion.pressIn
              : LumaNestMotion.pressOut,
          scale: _pressed ? .88 : 1,
          child: AnimatedContainer(
            duration: widget.reduceMotion
                ? Duration.zero
                : LumaNestMotion.containerTransform,
            curve: LumaNestMotion.emphasized,
            width: widget.isolated ? 64 : null,
            height: widget.isolated ? 64 : null,
            decoration: widget.isolated
                ? BoxDecoration(
                    color: widget.selected
                        ? V2Palette.moss
                        : const Color(0xF7F4F4F1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .9),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: V2Palette.ink.withValues(alpha: .17),
                        blurRadius: 24,
                        offset: const Offset(0, 11),
                      ),
                    ],
                  )
                : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: _duration,
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .7, end: 1).animate(animation),
                    child: RotationTransition(
                      turns: Tween<double>(
                        begin: -.045,
                        end: 0,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                ),
                child: Icon(
                  widget.selected ? widget.item.selectedIcon : widget.item.icon,
                  key: ValueKey(widget.selected),
                  size: widget.isolated
                      ? 27
                      : widget.selected
                      ? 27
                      : 24,
                  color: widget.isolated && widget.selected
                      ? Colors.white
                      : widget.selected
                      ? V2Palette.moss
                      : V2Palette.mutedInk.withValues(alpha: .68),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
