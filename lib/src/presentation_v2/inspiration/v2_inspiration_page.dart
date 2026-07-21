// ignore_for_file: unused_element, prefer_final_fields

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
        loading: () => const _InspirationFallbackFrame(
          child: V2LoadingObject(label: '正在收拢此刻灵感'),
        ),
        error: (_, _) => _InspirationFallbackFrame(
          child: SafeArea(
            child: V2EmptyObject(
              icon: CupertinoIcons.sparkles,
              title: '灵感暂时没有接住环境',
              detail: '更新当前环境后再试。',
              action: '重新获取',
              onAction: () =>
                  ref.read(environmentSnapshotProvider.notifier).refresh(),
            ),
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

/// The immersive inspiration surface hides the navigation dock, so every
/// state — including loading and error fallbacks — must keep its own exit.
class _InspirationFallbackFrame extends StatelessWidget {
  const _InspirationFallbackFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      child,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 20, top: 9),
          child: Semantics(
            button: true,
            label: '关闭',
            child: InkWell(
              onTap: () => context.go('/today'),
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: V2Palette.paper.withValues(alpha: .3),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: V2Palette.paper,
                  size: 23,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
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
  final _inputController = TextEditingController();

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
  void dispose() {
    _inputController.dispose();
    super.dispose();
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

    return Material(
      color: V2Palette.paper,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _inspirationTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _inspirationWall(notes),
                    const SizedBox(height: 24),
                    const Text(
                      '想去哪里？',
                      style: TextStyle(
                        color: V2Palette.ink,
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      '我可以帮你发现附近灵感、活动、路线',
                      style: TextStyle(
                        color: V2Palette.mutedInk,
                        fontSize: 22,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _recommendation('日出和银河去哪？'),
                    const SizedBox(height: 11),
                    _recommendation('附近适合拍什么？'),
                    if (notes.isEmpty) ...[
                      const SizedBox(height: 18),
                      TextButton.icon(
                        onPressed: () => context.go('/explore'),
                        icon: const Icon(CupertinoIcons.compass),
                        label: const Text('去探索收集灵感'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _inspirationTopBar(BuildContext context) => SizedBox(
    height: 70,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Text(
          '灵感',
          style: TextStyle(
            color: V2Palette.ink,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: _circleAction(
              CupertinoIcons.xmark,
              '关闭',
              () => context.go('/today'),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: _circleAction(
              CupertinoIcons.line_horizontal_3,
              '更多推荐',
              _showInspirationMenu,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _circleAction(IconData icon, String label, VoidCallback onTap) =>
      Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: V2Palette.line.withValues(alpha: .6)),
            ),
            child: Icon(icon, color: V2Palette.ink, size: 23),
          ),
        ),
      );

  Widget _inspirationWall(List<InspirationNote> notes) {
    const defaults = <String>[
      '晨光落在水面',
      '沿着风去看海',
      '把街巷拍成电影',
      '今晚看星星',
      '找一处安静的山',
      '给旅程留一张纸条',
    ];
    final source = notes
        .map((note) => note.displayLabel)
        .toList(growable: false);
    // 纸条墙固定 3 行 × 每行 2 张：优先真实灵感、去重，不足用默认补齐。
    // 每张只出现一次，整墙不横向滚动，因此不会被边缘截断。
    final wallNotes = <String>{...source, ...defaults}
        .take(6)
        .toList(growable: false);
    final colors = <Color>[
      const Color(0xFFFFF4D9),
      const Color(0xFFEAF4E6),
      const Color(0xFFEAF1FA),
      const Color(0xFFFFE8E3),
      const Color(0xFFF1EAF8),
    ];
    return Column(
      children: List.generate(3, (row) {
        final rowNotes = wallNotes
            .skip(row * 2)
            .take(2)
            .toList(growable: false);
        return Padding(
          padding: EdgeInsets.only(
            left: row.isOdd ? 38 : 0,
            bottom: row < 2 ? 8 : 0,
          ),
          child: Row(
            children: [
              for (int item = 0; item < rowNotes.length; item++) ...[
                if (item > 0) const SizedBox(width: 10),
                Expanded(
                  child: _noteTile(
                    rowNotes[item],
                    color: colors[(item + row * 2) % colors.length],
                    tilt: ((item + row) % 3 - 1) * .018,
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }

  Widget _noteTile(
    String label, {
    required Color color,
    required double tilt,
  }) => Transform.rotate(
    angle: tilt,
    child: InkWell(
      onTap: () => _openTopic(label),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: .05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );

  Widget _recommendation(String label) => InkWell(
    onTap: () => _openTopic(label),
    borderRadius: BorderRadius.circular(40),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: V2Palette.canvas,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.sparkles, color: V2Palette.moss, size: 18),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Icon(CupertinoIcons.arrow_up_right, color: V2Palette.mutedInk),
        ],
      ),
    ),
  );

  Widget _composer() => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      10,
      22,
      14 +
          MediaQuery.viewInsetsOf(context).bottom +
          MediaQuery.paddingOf(context).bottom,
    ),
    child: Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: V2Palette.paper,
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: V2Palette.line.withValues(alpha: .6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.plus, size: 28, color: V2Palette.ink),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitComposer(),
              decoration: const InputDecoration(
                hintText: '发消息或按住说话',
                hintStyle: TextStyle(
                  color: Color(0xFFBFC2BE),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          IconButton(
            tooltip: '语音输入',
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('语音输入即将支持，先用文字告诉我吧。'))),
            icon: const Icon(CupertinoIcons.mic_fill, size: 25),
            color: V2Palette.ink,
          ),
        ],
      ),
    ),
  );

  void _submitComposer() {
    final question = _inputController.text.trim();
    if (question.isEmpty) return;
    _inputController.clear();
    _openTopic(question);
  }

  void _openTopic(String topic) => showAskLumaNestSheet(
    context,
    snapshot: widget.snapshot,
    surface: 'inspiration',
    judgement: topic,
    eventIds: widget.snapshot.shootingSessions.map((session) => session.id),
    initialQuestion: topic,
  );

  void _showInspirationMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: V2Palette.paper,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          children: [
            const Text(
              '推荐话题',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final topic in const ['帮我创建出行计划', '帮我解析行程/地点', '需要带什么器材？'])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(topic),
                trailing: const Icon(CupertinoIcons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  _openTopic(topic);
                },
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
                    inspirationNotes: notes,
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
