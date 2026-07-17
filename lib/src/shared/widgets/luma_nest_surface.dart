import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design/luma_nest_colors.dart';
import '../../design/luma_nest_text_styles.dart';
import 'luma_nest_brand_mark.dart';

/// Shared semantic surfaces. Content chooses a role rather than inventing its
/// own opacity, border and corner treatment on every page.
///
/// Glass blur is reserved for [mapOverlay] (and the navigation island in
/// `AppShell`). Ordinary content and settings surfaces ([mist], [solid]) stay
/// opaque and borderless so the ambient canvas carries the atmosphere instead
/// of every card.
enum LumaNestSurfaceTone {
  /// Quiet default content surface. Opaque, no border, no blur.
  mist,

  /// Warm editorial paper for brand and 纸条 surfaces. Opaque with a subtle
  /// paper hairline.
  paper,

  /// Solid grouped surface for settings and lists. Opaque, no border.
  solid,

  /// Floating map overlay. Translucent with glass blur and a hairline so it
  /// stays legible over moving map content.
  mapOverlay,

  /// Safety / error surface.
  safety,
}

class LumaNestSurface extends StatelessWidget {
  const LumaNestSurface({
    super.key,
    required this.child,
    this.tone = LumaNestSurfaceTone.mist,
    this.padding,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(LumaNestRadii.regular),
    ),
    this.onTap,
  });

  final Widget child;
  final LumaNestSurfaceTone tone;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (color, border, blur) = _resolve(tone, context);
    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: border == null ? null : Border.all(color: border),
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

  (Color, Color?, bool) _resolve(
    LumaNestSurfaceTone tone,
    BuildContext context,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (tone) {
      case LumaNestSurfaceTone.mist:
        // Quiet, opaque content surface. No glass, no border — the ambient
        // canvas supplies atmosphere, the surface stays legible.
        return (scheme.surface.withValues(alpha: .82), null, false);
      case LumaNestSurfaceTone.paper:
        return (
          dark
              ? const Color(0xFF29251F).withValues(alpha: .94)
              : const Color(0xFFF3E9D9).withValues(alpha: .94),
          dark
              ? const Color(0xFFE2C9A8).withValues(alpha: .24)
              : const Color(0xFF806C55).withValues(alpha: .28),
          false,
        );
      case LumaNestSurfaceTone.mapOverlay:
        // Glass + hairline: reserved for floating map layers.
        return (
          scheme.surface.withValues(alpha: .88),
          scheme.outlineVariant.withValues(alpha: .7),
          true,
        );
      case LumaNestSurfaceTone.safety:
        return (
          scheme.errorContainer,
          scheme.error.withValues(alpha: .28),
          false,
        );
      case LumaNestSurfaceTone.solid:
        // Opaque settings/list surface. No glass, no border — internal
        // dividers separate rows instead of a uniform card outline.
        return (scheme.surfaceContainerLow.withValues(alpha: .96), null, false);
    }
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
        const LumaNestBrandMark(size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: LumaNestTextStyles.brandLabel(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        ?trailing,
      ],
    );
  }
}
