import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/scenario/surface_composition.dart';
import 'package:luma_nest/src/presentation_v2/entry/entry_action_dispatcher.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_opportunity_object.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

abstract final class EntryCardRegistry {
  static Widget build(
    BuildContext context,
    ContextEntry entry,
    CompositionSlot slot, {
    ContextSnapshot? snapshot,
    VoidCallback? onCollapse,
  }) {
    if (entry.kind == EntryKind.safety &&
        slot == CompositionSlot.blockingSafety) {
      return _SafetyEntryCard(
        entry: entry,
        onTap: () =>
            EntryActionDispatcher.dispatch(context, entry, snapshot: snapshot),
        onCollapse: onCollapse,
      );
    }
    return V2OpportunityObject(
      stableId: _heroId(entry),
      eyebrow: entry.presentation.eyebrow,
      title: entry.presentation.title,
      detail: entry.presentation.detail,
      timeLabel: entry.presentation.timeLabel,
      actionLabel: entry.presentation.actionLabel,
      accent: _accent(context, entry.presentation.accent),
      onTap: () =>
          EntryActionDispatcher.dispatch(context, entry, snapshot: snapshot),
    );
  }

  static String _heroId(ContextEntry entry) {
    final payload = entry.payload;
    if (payload is OpportunityEntryPayload && payload.sessionId != null) {
      return payload.sessionId!;
    }
    return entry.sourceId;
  }

  static Color _accent(BuildContext context, EntryAccent value) =>
      switch (value) {
        EntryAccent.sky => context.v2Sky,
        EntryAccent.moss => context.v2Moss,
        EntryAccent.ember => context.v2Ember,
        EntryAccent.mutedInk => context.v2MutedInk,
        EntryAccent.night => context.v2Night,
        EntryAccent.danger => context.v2Danger,
      };
}

class _SafetyEntryCard extends StatelessWidget {
  const _SafetyEntryCard({
    required this.entry,
    required this.onTap,
    this.onCollapse,
  });

  final ContextEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) => V2Pressable(
    key: const Key('v2-safety-object'),
    onTap: onTap,
    color: context.v2DangerSoft,
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.shield_lefthalf_fill,
                color: context.v2Danger,
                size: 34,
              ),
              const Spacer(),
              Text(
                entry.presentation.eyebrow,
                style: TextStyle(
                  color: context.v2Danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                entry.presentation.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.v2Ink,
                  fontSize: 29,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '查看官方依据与行动建议  →',
                style: TextStyle(
                  color: context.v2Ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (onCollapse != null)
          Positioned(
            top: 16,
            right: 18,
            child: TextButton(
              key: const Key('v2-safety-collapse'),
              onPressed: onCollapse,
              style: TextButton.styleFrom(
                foregroundColor: context.v2Danger,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('收起'),
            ),
          ),
      ],
    ),
  );
}
