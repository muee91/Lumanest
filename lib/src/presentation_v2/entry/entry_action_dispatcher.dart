import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/entry/context_entry.dart';
import 'package:luma_nest/src/core/entry/entry_action.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

abstract final class EntryActionDispatcher {
  static Future<void> dispatch(
    BuildContext context,
    ContextEntry entry, {
    ContextSnapshot? snapshot,
  }) async {
    final action = entry.actions.firstOrNull;
    if (action == null) return;
    switch (action.type) {
      case EntryActionType.openShootingWindow:
        final id = action.targetId;
        if (id != null) {
          context.push('/session/${Uri.encodeComponent(id)}', extra: snapshot);
        }
      case EntryActionType.openExplore:
        final query = action.query;
        context.go(query == null ? '/explore' : '/explore?focus=$query');
      case EntryActionType.openRoute:
        context.go('/route');
      case EntryActionType.openPlaceDetail:
        final id = action.targetId;
        context.go(
          id == null ? '/explore' : '/place/${Uri.encodeComponent(id)}',
        );
      case EntryActionType.openAstronomyDetail:
        final target = action.targetId;
        final parts = target?.split(':') ?? const <String>[];
        if (parts.length == 2 && int.tryParse(parts[1]) != null) {
          context.push('/sky-opportunity/${parts[0]}/${parts[1]}');
        } else {
          await handleManifestAction(
            context,
            _legacyItem(entry, ManifestAction.openAstronomyDetail),
          );
        }
      case EntryActionType.openWildlifeDetail:
        await handleManifestAction(
          context,
          _legacyItem(entry, ManifestAction.openWildlifeDetail),
        );
      case EntryActionType.openSafetyDetail:
        await handleManifestAction(
          context,
          _legacyItem(entry, ManifestAction.openSafetyDetail),
          detailOverride: entry.presentation.detail == '查看依据与行动建议'
              ? null
              : entry.presentation.detail,
        );
      case EntryActionType.openCreativeDetail:
        await handleManifestAction(
          context,
          _legacyItem(entry, ManifestAction.openCreativeDetail),
        );
      case EntryActionType.dismiss:
        return;
    }
  }

  static ManifestItem _legacyItem(ContextEntry entry, ManifestAction action) {
    return ManifestItem(
      id: entry.sourceId,
      title: entry.presentation.title,
      action: action,
      observedAt: entry.observedAt,
      expiresAt: entry.expiresAt,
      safetyLevel: entry.kind == EntryKind.safety
          ? ContextSafetyLevel.warning
          : null,
      authorityUri: entry.provenance
          .map((item) => item.sourceUri)
          .whereType<Uri>()
          .firstOrNull,
      // Deliberately omit confidence: evidenceConfidence is an internal
      // qualification signal, not a user-facing probability.
      confidence: null,
    );
  }
}
