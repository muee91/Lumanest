import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:luma_nest/src/design/luma_nest_motion.dart';

import 'v2_palette.dart';
import 'v2_stage.dart';

class V2OpportunityObject extends StatelessWidget {
  const V2OpportunityObject({
    super.key,
    required this.stableId,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.actionLabel,
    required this.onTap,
    this.accent,
    this.expanded = false,
    this.trailing,
  });

  final String stableId;
  final String eyebrow;
  final String title;
  final String detail;
  final String timeLabel;
  final String actionLabel;
  final VoidCallback onTap;
  final Color? accent;
  final bool expanded;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? context.v2Moss;
    return Hero(
      tag: 'v2-opportunity:$stableId',
      transitionOnUserGestures: true,
      flightShuttleBuilder:
          (context, animation, direction, fromContext, toContext) {
            final sourceHero = direction == HeroFlightDirection.push
                ? fromContext.widget
                : toContext.widget;
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: const Interval(0, .86, curve: LumaNestMotion.standard),
              ),
              child: Material(
                color: Colors.transparent,
                child: (sourceHero as Hero).child,
              ),
            );
          },
      child: Material(
        color: Colors.transparent,
        child: V2Pressable(
          onTap: onTap,
          color: context.v2Paper,
          semanticLabel: '$title，$actionLabel',
          haptic: HapticFeedback.mediumImpact,
          child: AnimatedContainer(
            duration: V2MotionScope.of(context)
                ? Duration.zero
                : LumaNestMotion.containerTransform,
            curve: LumaNestMotion.emphasized,
            height: expanded ? 360 : null,
            padding: EdgeInsets.fromLTRB(
              expanded ? 28 : 24,
              expanded ? 30 : 24,
              expanded ? 28 : 24,
              expanded ? 26 : 22,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        eyebrow,
                        style: TextStyle(
                          color: context.v2MutedInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                SizedBox(height: expanded ? 34 : 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(
                          title,
                          maxLines: expanded ? 4 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.v2Ink,
                            fontSize: expanded ? 34 : 30,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        flex: 2,
                        child: Text(
                          detail,
                          maxLines: expanded ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.v2MutedInk,
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(CupertinoIcons.clock, color: accentColor, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        timeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.v2Ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
