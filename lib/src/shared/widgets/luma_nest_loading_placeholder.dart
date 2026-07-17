import 'package:flutter/material.dart';

import 'luma_nest_brand_mark.dart';
import 'luma_nest_surface.dart';

/// A branded, quiet loading placeholder.
///
/// Designed to sit over the ambient canvas or a map without breaking
/// readability: it paints on a [LumaNestSurfaceTone.mist] fill (opaque, no
/// glass), uses theme colors so high-contrast themes stay legible, and falls
/// back to a static ring when animations are disabled (reduce motion /
/// accessibility) so it never relies on motion to communicate state.
class LumaNestLoadingPlaceholder extends StatelessWidget {
  const LumaNestLoadingPlaceholder({
    super.key,
    this.label,
    this.tone = LumaNestSurfaceTone.mist,
    this.compact = false,
  });

  /// Optional accessible label. When null, the placeholder exposes a generic
  /// semantics label so screen readers still announce the loading state.
  final String? label;

  /// Surface tone. Defaults to [LumaNestSurfaceTone.mist] for ordinary
  /// content; pass [LumaNestSurfaceTone.mapOverlay] when floating over a map.
  final LumaNestSurfaceTone tone;

  /// Reduces the brand mark size and padding for inline use.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final markSize = compact ? 22.0 : 30.0;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label ?? '正在加载',
      child: LumaNestSurface(
        tone: tone,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 22,
          vertical: compact ? 14 : 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LumaNestBrandMark(size: markSize),
            if (label != null) ...[
              const SizedBox(height: 10),
              Text(
                label!,
                style:
                    (compact
                            ? theme.textTheme.labelMedium
                            : theme.textTheme.titleSmall)
                        ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ],
            const SizedBox(height: 12),
            _QuietIndicator(
              color: theme.colorScheme.primary,
              reduceMotion: reduceMotion,
              size: compact ? 16 : 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietIndicator extends StatelessWidget {
  const _QuietIndicator({
    required this.color,
    required this.reduceMotion,
    required this.size,
  });

  final Color color;
  final bool reduceMotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      // Static ring: communicates "in progress" without motion for reduce
      // motion / accessibility settings.
      return SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}
