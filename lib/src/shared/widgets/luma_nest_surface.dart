import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared semantic surfaces. Content chooses a role rather than inventing its
/// own opacity, border and corner treatment on every page.
enum LumaNestSurfaceTone { mist, solid, mapOverlay, safety }

class LumaNestSurface extends StatelessWidget {
  const LumaNestSurface({
    super.key,
    required this.child,
    this.tone = LumaNestSurfaceTone.mist,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.onTap,
  });

  final Widget child;
  final LumaNestSurfaceTone tone;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, border, blur) = switch (tone) {
      LumaNestSurfaceTone.mist => (
        scheme.surface.withValues(alpha: .72),
        scheme.outlineVariant.withValues(alpha: .52),
        true,
      ),
      LumaNestSurfaceTone.mapOverlay => (
        scheme.surface.withValues(alpha: .88),
        scheme.outlineVariant.withValues(alpha: .7),
        true,
      ),
      LumaNestSurfaceTone.safety => (
        scheme.errorContainer,
        scheme.error.withValues(alpha: .28),
        false,
      ),
      LumaNestSurfaceTone.solid => (
        scheme.surfaceContainerLow.withValues(alpha: .96),
        scheme.outlineVariant.withValues(alpha: .72),
        false,
      ),
    };

    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: border),
      ),
      // A transparent Material directly above the painted surface preserves
      // ListTile ink, focus highlights and descendant InkWells.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
    if (blur) {
      result = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: result,
        ),
      );
    }
    if (onTap != null) {
      result = Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: borderRadius, onTap: onTap, child: result),
      );
    }
    return result;
  }
}

class LumaNestEyebrow extends StatelessWidget {
  const LumaNestEyebrow({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: .35,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
