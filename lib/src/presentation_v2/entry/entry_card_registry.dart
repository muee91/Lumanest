import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
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
    VoidCallback? onCollapse,
  }) {
    if (entry.kind == EntryKind.safety &&
        slot == CompositionSlot.blockingSafety) {
      return _SafetyEntryCard(
        entry: entry,
        onTap: () => EntryActionDispatcher.dispatch(context, entry),
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
      accent: _accent(entry.presentation.accent),
      onTap: () => EntryActionDispatcher.dispatch(context, entry),
    );
  }

  static String _heroId(ContextEntry entry) {
    final payload = entry.payload;
    if (payload is OpportunityEntryPayload && payload.sessionId != null) {
      return payload.sessionId!;
    }
    return entry.sourceId;
  }

  static Color _accent(EntryAccent value) => switch (value) {
    EntryAccent.sky => V2Palette.sky,
    EntryAccent.moss => V2Palette.moss,
    EntryAccent.ember => V2Palette.ember,
    EntryAccent.mutedInk => V2Palette.mutedInk,
    EntryAccent.night => V2Palette.night,
    EntryAccent.danger => V2Palette.danger,
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
    color: V2Palette.dangerSoft,
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                CupertinoIcons.shield_lefthalf_fill,
                color: V2Palette.danger,
                size: 34,
              ),
              const Spacer(),
              Text(
                entry.presentation.eyebrow,
                style: const TextStyle(
                  color: V2Palette.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                entry.presentation.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 29,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '查看官方依据与行动建议  →',
                style: TextStyle(
                  color: V2Palette.ink,
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
                foregroundColor: V2Palette.danger,
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
