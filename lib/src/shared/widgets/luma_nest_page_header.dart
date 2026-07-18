import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/luma_nest_brand_mark.dart';

class LumaNestPageHeader extends StatelessWidget {
  const LumaNestPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow = '栖光',
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 14),
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: LumaNestBrandMark(size: 22),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}
