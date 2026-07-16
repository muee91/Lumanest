import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Keeps related actions horizontal at the default text size and gives each
/// action the full available width when accessibility text would make labels
/// compete for space.
class ResponsiveActionGroup extends StatelessWidget {
  const ResponsiveActionGroup({
    super.key,
    required this.actions,
    this.spacing = 8,
    this.stackAtTextScale = 1.3,
  }) : assert(actions.length > 0);

  final List<Widget> actions;
  final double spacing;
  final double stackAtTextScale;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            actions.length > 1 &&
            (textScale >= stackAtTextScale || constraints.maxWidth < 320);
        final orderedActions = [
          for (var index = 0; index < actions.length; index++)
            Semantics(
              sortKey: OrdinalSortKey(index.toDouble()),
              child: SizedBox(width: double.infinity, child: actions[index]),
            ),
        ];
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < orderedActions.length; index++) ...[
                orderedActions[index],
                if (index != orderedActions.length - 1)
                  SizedBox(height: spacing),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < orderedActions.length; index++) ...[
              Expanded(child: orderedActions[index]),
              if (index != orderedActions.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}
