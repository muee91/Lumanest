import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/companion/companion_client.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/feedback/luma_nest_feedback_service.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/narrative/manifest_narrative_providers.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/inspiration/presentation/widgets/inspiration_bottle.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

class V2InspirationPage extends ConsumerWidget {
  const V2InspirationPage({super.key});

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
            title: '瓶子暂时没有接住环境',
            detail: '更新当前环境后，创作纸条会重新出现。',
            action: '重新获取',
            onAction: () =>
                ref.read(environmentSnapshotProvider.notifier).refresh(),
          ),
        ),
        data: (value) => _V2InspirationStage(snapshot: value),
      ),
    );
  }
}

class _V2InspirationStage extends ConsumerStatefulWidget {
  const _V2InspirationStage({required this.snapshot});
  final ContextSnapshot snapshot;

  @override
  ConsumerState<_V2InspirationStage> createState() =>
      _V2InspirationStageState();
}

class _V2InspirationStageState extends ConsumerState<_V2InspirationStage> {
  int _selectedIndex = 0;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(profilePreferencesProvider);
    final narrative = ref
        .watch(manifestNarrativeProvider(widget.snapshot))
        .asData
        ?.value;
    final localNotes = InspirationNotes.build(
      widget.snapshot,
      narrative: narrative,
      availableEquipment: EquipmentCapabilityParser.parse(
        preferences.equipmentList,
      ),
    );
    final remoteInsights =
        ref.watch(companionInventoryProvider).asData?.value ?? const [];
    final remoteByNote = <String, CompanionInsight>{};
    final notes = <InspirationNote>[];
    for (final insight in remoteInsights) {
      final note = insight.toInspirationNote(DateTime.now());
      if (note == null || remoteByNote.containsKey(note.id)) continue;
      remoteByNote[note.id] = insight;
      notes.add(note);
    }
    notes.addAll(
      localNotes.where((note) => !remoteByNote.containsKey(note.id)),
    );
    if (notes.isEmpty) {
      return SafeArea(
        child: V2EmptyObject(
          icon: CupertinoIcons.sparkles,
          title: '瓶子里暂时没有纸条',
          detail: '去地图走一走，新的场景会带来新的创作方向。',
          action: '去探索',
          onAction: () => context.go('/explore'),
        ),
      );
    }
    final selectedIndex = _selectedIndex.clamp(0, notes.length - 1);
    if (selectedIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedIndex = selectedIndex);
      });
    }
    final note = notes[selectedIndex];
    final library = ref.watch(userLibraryProvider).asData?.value;
    final savedId = SavedInspirationNote.idFor(
      snapshotId: widget.snapshot.id,
      noteId: note.id,
    );
    final saved = library?.savedNotes.any((item) => item.id == savedId) == true;
    final reduceMotion =
        preferences.reduceMotion || MediaQuery.disableAnimationsOf(context);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 102),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '灵感瓶',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '抓住纸条，把它从瓶里带出来',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          '${notes.length} 张',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: Duration(milliseconds: reduceMotion ? 0 : 480),
                  curve: Curves.easeOutBack,
                  left: _open ? 14 : 0,
                  right: _open ? 14 : 0,
                  top: _open ? (compact ? 86 : 106) : (compact ? 98 : 132),
                  height: _open ? (compact ? 330 : 390) : (compact ? 360 : 430),
                  child: AnimatedOpacity(
                    duration: Duration(milliseconds: reduceMotion ? 0 : 220),
                    opacity: _open ? .22 : 1,
                    child: IgnorePointer(
                      ignoring: _open,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.fromSeed(
                              seedColor: V2Palette.moss,
                              brightness: Brightness.dark,
                            ),
                          ),
                          child: InspirationBottle(
                            snapshotId: widget.snapshot.id,
                            notes: notes,
                            selectedId: note.id,
                            reduceMotion: reduceMotion,
                            enableShake: !reduceMotion,
                            onDraw: () => _draw(notes.length),
                            onSelect: (value) => _select(notes, value),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  key: Key('v2-inspiration-slip-${note.id}'),
                  duration: Duration(milliseconds: reduceMotion ? 0 : 520),
                  curve: Curves.easeOutCubic,
                  left: _open ? 0 : constraints.maxWidth * .28,
                  right: _open ? 0 : constraints.maxWidth * .28,
                  top: _open
                      ? (compact ? 94 : 116)
                      : constraints.maxHeight * .55,
                  height: _open ? (compact ? 340 : 410) : 58,
                  child: IgnorePointer(
                    ignoring: !_open,
                    child: AnimatedOpacity(
                      duration: Duration(milliseconds: reduceMotion ? 0 : 260),
                      opacity: _open ? 1 : 0,
                      child: _V2InspirationSlip(
                        note: note,
                        saved: saved,
                        onReturn: () => setState(() => _open = false),
                        onNext: () => _draw(notes.length),
                        onSave: saved ? null : () => _save(note, remoteByNote),
                        onAction: () => _act(note, remoteByNote),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      V2Pressable(
                        key: const Key('v2-draw-inspiration'),
                        onTap: () => _draw(notes.length),
                        color: V2Palette.moss,
                        sound: LumaNestSound.paper,
                        haptic: LumaNestHaptic.selection,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 15,
                          ),
                          child: Text(
                            _open ? '继续抽取' : '抽一张',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _draw(int length) {
    if (length == 0) return;
    setState(() {
      _selectedIndex = _open ? (_selectedIndex + 1) % length : _selectedIndex;
      _open = true;
    });
  }

  void _select(List<InspirationNote> notes, InspirationNote note) {
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    setState(() {
      _selectedIndex = index;
      _open = true;
    });
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
    handleManifestAction(
      context,
      ManifestItem(
        id: note.id,
        title: note.displayLabel,
        action: note.action,
        authorityUri: note.authorityUri,
      ),
      detailOverride: note.detail,
    );
  }
}

class _V2InspirationSlip extends StatelessWidget {
  const _V2InspirationSlip({
    required this.note,
    required this.saved,
    required this.onReturn,
    required this.onNext,
    required this.onAction,
    this.onSave,
  });
  final InspirationNote note;
  final bool saved;
  final VoidCallback onReturn;
  final VoidCallback onNext;
  final VoidCallback onAction;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFFBEC),
    elevation: 22,
    shadowColor: Colors.black54,
    borderRadius: BorderRadius.circular(30),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(25, 22, 25, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                note.isFactual ? '此刻机会' : '创作方向',
                style: const TextStyle(
                  color: V2Palette.moss,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onReturn,
                icon: const Icon(CupertinoIcons.arrow_down),
                tooltip: '放回瓶中',
              ),
            ],
          ),
          const Spacer(),
          Text(
            note.displayLabel,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 30,
              height: 1.12,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            note.detail,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 14,
              height: 1.45,
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
                onTap: onSave == null ? () {} : () => unawaited(onSave!()),
              ),
              const SizedBox(width: 10),
              V2RoundAction(
                icon: CupertinoIcons.arrow_2_circlepath,
                label: '继续抽取',
                onTap: onNext,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: V2Pressable(
                  onTap: onAction,
                  color: V2Palette.moss,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
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
  );
}
