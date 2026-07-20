import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/companion/companion_client.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/sky_opportunity/application/sky_opportunity_providers.dart';
import 'package:luma_nest/src/presentation_v2/ai/v2_ask_luma_nest.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

class V2InspirationPage extends ConsumerWidget {
  const V2InspirationPage({super.key, this.initialNoteId});

  final String? initialNoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(environmentSnapshotProvider);
    return ColoredBox(
      color: V2Palette.night,
      child: snapshot.when(
        loading: () => const V2LoadingObject(label: '正在收拢此刻灵感'),
        error: (_, _) => SafeArea(
          child: V2EmptyObject(
            icon: CupertinoIcons.sparkles,
            title: '灵感暂时没有接住环境',
            detail: '更新当前环境后再试。',
            action: '重新获取',
            onAction: () =>
                ref.read(environmentSnapshotProvider.notifier).refresh(),
          ),
        ),
        data: (value) => _InspirationWorkspace(
          snapshot: value,
          initialNoteId: initialNoteId,
        ),
      ),
    );
  }
}

class _InspirationWorkspace extends ConsumerStatefulWidget {
  const _InspirationWorkspace({required this.snapshot, this.initialNoteId});

  final ContextSnapshot snapshot;
  final String? initialNoteId;

  @override
  ConsumerState<_InspirationWorkspace> createState() =>
      _InspirationWorkspaceState();
}

class _InspirationWorkspaceState extends ConsumerState<_InspirationWorkspace> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(companionInventoryProvider.notifier)
          .refresh(
            snapshotId: widget.snapshot.id,
            reason: 'page_enter',
            visiblePage: 'inspiration',
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(profilePreferencesProvider);
    final narrative = ref
        .watch(manifestNarrativeProvider(widget.snapshot))
        .asData
        ?.value;
    final now = ref.watch(currentTimeProvider)();
    final point = widget.snapshot.location;
    final skyOpportunities = point == null
        ? const <Never>[]
        : ref
                  .watch(
                    dailySkyOpportunitiesProvider((
                      latitude: point.latitude,
                      longitude: point.longitude,
                      focus: skyOpportunityFocusForSnapshot(
                        widget.snapshot,
                        now,
                      ),
                    )),
                  )
                  .asData
                  ?.value
                  .values ??
              const [];
    final localNotes = InspirationNotes.build(
      widget.snapshot,
      narrative: narrative,
      skyOpportunities: skyOpportunities,
      availableEquipment: EquipmentCapabilityParser.parse(
        preferences.equipmentList,
      ),
    );
    final remoteInsights =
        ref.watch(companionInventoryProvider).asData?.value ?? const [];
    final remoteByNote = <String, CompanionInsight>{};
    final notes = <InspirationNote>[];
    for (final insight in remoteInsights) {
      final note = insight.toInspirationNote(now);
      if (note == null || remoteByNote.containsKey(note.id)) continue;
      remoteByNote[note.id] = insight;
      notes.add(note);
    }
    notes.addAll(
      localNotes.where((note) => !remoteByNote.containsKey(note.id)),
    );

    final requested = widget.initialNoteId == null
        ? -1
        : notes.indexWhere((note) => note.id == widget.initialNoteId);
    final index = notes.isEmpty
        ? 0
        : (requested >= 0 ? requested : _selectedIndex).clamp(
            0,
            notes.length - 1,
          );
    final selected = notes.isEmpty ? null : notes[index];
    final library = ref.watch(userLibraryProvider).asData?.value;
    final nearbyPlaces =
        ref.watch(nearbyPlacesProvider).asData?.value ?? const <NearbyPlace>[];

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.paddingOf(context).bottom + 96,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '灵感',
              style: TextStyle(
                color: Colors.white,
                fontSize: 29,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              '此刻能做什么',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 11,
              child: selected == null
                  ? _QuietInspiration(onExplore: () => context.go('/explore'))
                  : _InspirationArea(
                      notes: notes,
                      selectedIndex: index,
                      saved: _isSaved(library, selected),
                      onSelect: (next) => setState(() => _selectedIndex = next),
                      onShuffle: () => setState(() {
                        if (notes.length > 1) {
                          _selectedIndex = (index + 1) % notes.length;
                        }
                      }),
                      onSave: () => _save(selected, remoteByNote),
                      onAction: () => _act(selected, remoteByNote),
                    ),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 9,
              child: _InspirationAiArea(
                snapshot: widget.snapshot,
                notes: notes,
                selected: selected,
                places: nearbyPlaces,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSaved(UserLibraryState? library, InspirationNote note) {
    final id = SavedInspirationNote.idFor(
      snapshotId: widget.snapshot.id,
      noteId: note.id,
    );
    return library?.savedNotes.any((item) => item.id == id) == true;
  }

  Future<void> _save(
    InspirationNote note,
    Map<String, CompanionInsight> remoteByNote,
  ) async {
    await ref
        .read(userLibraryProvider.notifier)
        .saveInspirationNote(snapshotId: widget.snapshot.id, note: note);
    final insight = remoteByNote[note.id];
    if (insight != null) {
      await ref
          .read(companionInventoryProvider.notifier)
          .feedback(insight.id, InsightFeedbackAction.saved);
    }
  }

  void _act(InspirationNote note, Map<String, CompanionInsight> remoteByNote) {
    final insight = remoteByNote[note.id];
    if (insight != null) {
      unawaited(
        ref
            .read(companionInventoryProvider.notifier)
            .feedback(insight.id, InsightFeedbackAction.viewed),
      );
    }
    if (note.routeLocation case final route?) {
      context.push(route);
      return;
    }
    handleManifestAction(
      context,
      ManifestItem(
        id: note.id,
        title: note.label,
        action: note.action,
        authorityUri: note.authorityUri,
      ),
      detailOverride: note.detail,
    );
  }
}

class _InspirationArea extends StatelessWidget {
  const _InspirationArea({
    required this.notes,
    required this.selectedIndex,
    required this.saved,
    required this.onSelect,
    required this.onShuffle,
    required this.onSave,
    required this.onAction,
  });

  final List<InspirationNote> notes;
  final int selectedIndex;
  final bool saved;
  final ValueChanged<int> onSelect;
  final VoidCallback onShuffle;
  final Future<void> Function() onSave;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final note = notes[selectedIndex];
    return Column(
      children: [
        Expanded(
          child: Material(
            color: const Color(0xFFFFF8E7),
            elevation: 8,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(26),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 17, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.isFactual ? '此刻机会' : '创作方向',
                    style: const TextStyle(
                      color: V2Palette.moss,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    note.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: V2Palette.ink,
                      fontSize: 27,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.8,
                    ),
                  ),
                  if (notes.length > 1) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onShuffle,
                        icon: const Icon(
                          CupertinoIcons.arrow_2_squarepath,
                          size: 15,
                        ),
                        label: const Text('换一条'),
                        style: TextButton.styleFrom(
                          foregroundColor: V2Palette.moss,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    note.detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: V2Palette.mutedInk,
                      fontSize: 13,
                      height: 1.38,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      V2RoundAction(
                        icon: saved
                            ? CupertinoIcons.bookmark_fill
                            : CupertinoIcons.bookmark,
                        label: saved ? '已收藏' : '收藏',
                        onTap: saved ? () {} : () => unawaited(onSave()),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: V2Pressable(
                          key: const Key('v2-inspiration-navigation-action'),
                          onTap: onAction,
                          color: V2Palette.moss,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Text(
                              note.isFactual ? '查看机会' : '带去探索',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
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
        if (notes.length > 1) ...[
          const SizedBox(height: 9),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: notes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) => V2Pressable(
                onTap: () => onSelect(index),
                compact: true,
                color: index == selectedIndex
                    ? V2Palette.moss
                    : Colors.white.withValues(alpha: .12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Center(
                    child: Text(
                      notes[index].label,
                      maxLines: 1,
                      style: TextStyle(
                        color: index == selectedIndex
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InspirationAiArea extends StatelessWidget {
  const _InspirationAiArea({
    required this.snapshot,
    required this.notes,
    required this.selected,
    required this.places,
  });

  final ContextSnapshot snapshot;
  final List<InspirationNote> notes;
  final InspirationNote? selected;
  final List<NearbyPlace> places;

  @override
  Widget build(BuildContext context) {
    final prompts = <String>['把这个灵感变成具体拍法', '附近哪里适合实践？', '需要带什么器材？'];
    return Material(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(CupertinoIcons.sparkles, color: V2Palette.moss, size: 18),
                SizedBox(width: 7),
                Text(
                  '问栖光',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              selected == null ? '从附近地点和当前环境开始。' : '围绕「${selected!.label}」继续。',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: V2Palette.mutedInk, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: prompts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (context, index) => V2Pressable(
                  onTap: () => showAskLumaNestSheet(
                    context,
                    snapshot: snapshot,
                    surface: 'inspiration',
                    judgement: selected?.label ?? '创作灵感',
                    eventIds: [
                      ...snapshot.shootingSessions.map((session) => session.id),
                      ...snapshot.events.map((event) => event.id),
                    ].take(3),
                    places: places,
                    initialQuestion: prompts[index],
                  ),
                  compact: true,
                  color: index == 0 ? V2Palette.mossSoft : V2Palette.canvas,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            prompts[index],
                            style: const TextStyle(
                              color: V2Palette.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.arrow_up_right,
                          color: V2Palette.moss,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietInspiration extends StatelessWidget {
  const _QuietInspiration({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => V2EmptyObject(
    icon: CupertinoIcons.sparkles,
    title: '此刻没有明确灵感',
    detail: '去附近发现新的地点。',
    action: '去探索',
    onAction: onExplore,
  );
}
