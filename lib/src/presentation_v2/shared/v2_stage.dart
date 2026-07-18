import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/feedback/luma_nest_feedback_service.dart';
import 'package:luma_nest/src/design/luma_nest_motion.dart';

import 'v2_palette.dart';

class V2PageStage extends StatelessWidget {
  const V2PageStage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 10, 22, 104),
    this.backgroundColor = V2Palette.canvas,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: backgroundColor,
    child: SafeArea(
      bottom: false,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class V2TopLine extends StatelessWidget {
  const V2TopLine({
    super.key,
    required this.primary,
    required this.secondary,
    this.action,
    this.onAction,
  });

  final String primary;
  final String secondary;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              primary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 17,
                height: 1.1,
                fontWeight: FontWeight.w800,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              secondary,
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
      if (action != null && onAction != null)
        V2Pressable(
          onTap: onAction!,
          compact: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              action!,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
    ],
  );
}

class V2Pressable extends StatefulWidget {
  const V2Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.color = V2Palette.paper,
    this.compact = false,
    this.sound = LumaNestSound.click,
    this.haptic = LumaNestHaptic.lightImpact,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color color;
  final bool compact;
  final LumaNestSound sound;
  final LumaNestHaptic haptic;
  final String? semanticLabel;

  @override
  State<V2Pressable> createState() => _V2PressableState();
}

class _V2PressableState extends State<V2Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.semanticLabel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        LumaNestFeedbackService.instance.play(
          widget.sound,
          volume: .18,
          haptic: widget.haptic,
        );
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? .965 : 1,
        duration: _pressed ? LumaNestMotion.pressIn : LumaNestMotion.pressOut,
        curve: LumaNestMotion.emphasized,
        child: AnimatedContainer(
          duration: LumaNestMotion.pressOut,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(
              widget.compact ? V2Geometry.compact : V2Geometry.control,
            ),
            border: Border.all(color: V2Palette.line.withValues(alpha: .72)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? .04 : .08),
                blurRadius: _pressed ? 6 : 18,
                offset: Offset(0, _pressed ? 2 : 8),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

class V2RoundAction extends StatelessWidget {
  const V2RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = V2Palette.paper,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    color: color,
    semanticLabel: label,
    compact: true,
    child: SizedBox.square(
      dimension: 48,
      child: Icon(icon, color: V2Palette.ink, size: 21),
    ),
  );
}

class V2LoadingObject extends StatefulWidget {
  const V2LoadingObject({super.key, required this.label});

  final String label;

  @override
  State<V2LoadingObject> createState() => _V2LoadingObjectState();
}

class _V2LoadingObjectState extends State<V2LoadingObject>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: widget.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = (_controller.value - index * .17) % 1;
                final lift = (1 - (phase * 2 - 1).abs())
                    .clamp(0.0, 1.0)
                    .toDouble();
                return Transform.translate(
                  offset: Offset(0, -8 * lift),
                  child: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: V2Palette.moss,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.label,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class V2EmptyObject extends StatelessWidget {
  const V2EmptyObject({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: V2Palette.moss, size: 54),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 25,
            height: 1.15,
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: V2Palette.mutedInk,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        V2Pressable(
          onTap: onAction,
          color: V2Palette.mossSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            child: Text(
              action,
              style: const TextStyle(
                color: V2Palette.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class V2GrabHandle extends StatelessWidget {
  const V2GrabHandle({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 5,
    decoration: BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: .52)
          : V2Palette.ink.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(99),
    ),
  );
}

class V2BackButton extends StatelessWidget {
  const V2BackButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2RoundAction(
    icon: CupertinoIcons.chevron_left,
    label: '返回',
    onTap: onTap,
  );
}
