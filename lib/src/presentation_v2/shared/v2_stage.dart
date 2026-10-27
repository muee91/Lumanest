import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luma_nest/src/design/luma_nest_motion.dart';

import 'v2_palette.dart';

/// Carries the app's accessibility motion preference to every route in the
/// shell. Widgets outside the shell still fall back to the platform setting.
class V2MotionScope extends InheritedWidget {
  const V2MotionScope({
    super.key,
    required this.reduceMotion,
    required super.child,
  });

  final bool reduceMotion;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<V2MotionScope>()
          ?.reduceMotion ??
      MediaQuery.disableAnimationsOf(context);

  @override
  bool updateShouldNotify(V2MotionScope oldWidget) =>
      oldWidget.reduceMotion != reduceMotion;
}

class V2PageStage extends StatelessWidget {
  const V2PageStage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 10, 22, 104),
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final expanded = MediaQuery.sizeOf(context).width >= 900;
    final resolvedPadding = expanded && padding.bottom >= 80
        ? padding.copyWith(bottom: 32)
        : padding;
    return ColoredBox(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(padding: resolvedPadding, child: child),
      ),
    );
  }
}

class V2TopLine extends StatelessWidget {
  const V2TopLine({
    super.key,
    required this.primary,
    required this.secondary,
    this.action,
    this.onAction,
    this.trailing,
  });

  final String primary;
  final String secondary;
  final String? action;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
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
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 17,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                secondary,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
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
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
      ],
    );
  }
}

class V2Pressable extends StatefulWidget {
  const V2Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.color,
    this.compact = false,
    this.haptic = HapticFeedback.lightImpact,
    this.semanticLabel,
    this.semanticValue,
    this.toggled,
    this.onTapHint,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color? color;
  final bool compact;
  final Future<void> Function() haptic;
  final String? semanticLabel;
  final String? semanticValue;
  final bool? toggled;
  final String? onTapHint;

  @override
  State<V2Pressable> createState() => _V2PressableState();
}

class _V2PressableState extends State<V2Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = V2MotionScope.of(context);
    final pressIn = reduceMotion ? Duration.zero : LumaNestMotion.pressIn;
    final pressOut = reduceMotion ? Duration.zero : LumaNestMotion.pressOut;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      toggled: widget.toggled,
      hint: widget.onTapHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          unawaited(widget.haptic());
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? .965 : 1,
          duration: _pressed ? pressIn : pressOut,
          curve: LumaNestMotion.emphasized,
          child: AnimatedContainer(
            duration: pressOut,
            decoration: BoxDecoration(
              color:
                  widget.color ??
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(
                widget.compact ? V2Geometry.compact : V2Geometry.control,
              ),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .72),
              ),
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
}

class V2RoundAction extends StatelessWidget {
  const V2RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    color: color,
    semanticLabel: label,
    compact: true,
    child: SizedBox.square(
      dimension: 48,
      child: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurface,
        size: 21,
      ),
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
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = V2MotionScope.of(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        liveRegion: true,
        label: widget.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reduceMotion == true
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [_LoadingDot(), _LoadingDot(), _LoadingDot()],
                  )
                : AnimatedBuilder(
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
                          child: const _LoadingDot(),
                        );
                      }),
                    ),
                  ),
            const SizedBox(height: 20),
            Text(
              widget.label,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDot extends StatelessWidget {
  const _LoadingDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      shape: BoxShape.circle,
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
    this.secondaryAction,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onAction;
  final String? secondaryAction;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: context.v2Moss, size: 54),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.v2Ink,
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
          style: TextStyle(
            color: context.v2MutedInk,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        V2Pressable(
          onTap: onAction,
          color: context.v2MossSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            child: Text(
              action,
              style: TextStyle(
                color: context.v2Ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (secondaryAction != null && onSecondaryAction != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onSecondaryAction,
            child: Text(secondaryAction!),
          ),
        ],
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
          : context.v2Ink.withValues(alpha: .16),
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
