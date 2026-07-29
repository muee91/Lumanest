import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/assistant/assistant_intent.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// The single intelligent entrance for both free conversation and inspiration.
///
/// The upper stage owns inspiration and never scrolls with the conversation.
/// The lower stage owns assistant history and its composer. When the composer
/// gains focus, only the inspiration stage contracts; the page itself is not
/// placed inside a scroll view, so the keyboard cannot reorder the surface.
class V2IntelligencePage extends ConsumerWidget {
  const V2IntelligencePage({
    super.key,
    this.initialSnapshot,
    this.initialNoteId,
  });

  final ContextSnapshot? initialSnapshot;
  final String? initialNoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = initialSnapshot == null
        ? ref.watch(environmentSnapshotProvider)
        : AsyncData(initialSnapshot!);
    return Scaffold(
      key: const Key('v2-intelligence-page'),
      resizeToAvoidBottomInset: false,
      backgroundColor: V2Palette.paper,
      body: snapshot.when(
        loading: () => const V2LoadingObject(label: '正在准备此刻灵感'),
        error: (_, _) => SafeArea(
          child: V2EmptyObject(
            icon: CupertinoIcons.sparkles,
            title: '栖光暂时没有接住环境',
            detail: '刷新当前环境后，仍可从同一个入口提问或抽取灵感。',
            action: '关闭栖光',
            onAction: () => _close(context),
          ),
        ),
        data: (value) => _IntelligenceWorkspace(
          snapshot: value,
          initialNoteId: initialNoteId,
        ),
      ),
    );
  }

  static void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/today');
    }
  }
}

enum _IntelligenceLayoutState { home, inspiration, conversation, typing }

enum _PendingPhase { thinking, generating }

class _IntelligenceWorkspace extends ConsumerStatefulWidget {
  const _IntelligenceWorkspace({required this.snapshot, this.initialNoteId});

  final ContextSnapshot snapshot;
  final String? initialNoteId;

  @override
  ConsumerState<_IntelligenceWorkspace> createState() =>
      _IntelligenceWorkspaceState();
}

class _IntelligenceWorkspaceState
    extends ConsumerState<_IntelligenceWorkspace> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _conversationScroll = ScrollController();

  late AssistantConversationState _conversation;
  InspirationNote? _selectedNote;
  AssistantIntent? _pendingIntent;
  String _pendingText = '';
  String? _pendingSource;
  _PendingPhase? _pendingPhase;
  AssistantFailure? _lastFailure;
  CancelToken? _cancelToken;
  int _generation = 0;
  int _noteOffset = 0;
  bool _initialNoteResolved = false;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _conversation = AssistantConversationState(id: _newConversationId());
    _inputFocus.addListener(_handleInputFocus);
  }

  @override
  void didUpdateWidget(covariant _IntelligenceWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.id == widget.snapshot.id) return;
    _generation += 1;
    _cancelToken?.cancel('snapshot_changed');
    _cancelToken = null;
    _conversation = AssistantConversationState(id: _newConversationId());
    _selectedNote = null;
    _initialNoteResolved = false;
    _clearPending();
  }

  @override
  void dispose() {
    _generation += 1;
    _cancelToken?.cancel('intelligence_surface_disposed');
    _inputFocus
      ..removeListener(_handleInputFocus)
      ..dispose();
    _inputController.dispose();
    _conversationScroll.dispose();
    super.dispose();
  }

  void _handleInputFocus() {
    if (mounted) setState(() {});
  }

  _IntelligenceLayoutState get _layoutState {
    if (_inputFocus.hasFocus) return _IntelligenceLayoutState.typing;
    if (_conversation.turns.isNotEmpty || _pendingIntent != null) {
      return _IntelligenceLayoutState.conversation;
    }
    if (_selectedNote != null) return _IntelligenceLayoutState.inspiration;
    return _IntelligenceLayoutState.home;
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(profilePreferencesProvider);
    final notes = InspirationNotes.build(
      widget.snapshot,
      availableEquipment: EquipmentCapabilityParser.parse(
        preferences.equipmentList,
      ),
    );
    _resolveInitialNote(notes);
    final visibleNotes = _rotatedNotes(notes);
    final library = ref.watch(userLibraryProvider).asData?.value;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafe = keyboardHeight > 0
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final usableHeight = (constraints.maxHeight - keyboardHeight).clamp(
            280.0,
            constraints.maxHeight,
          );
          final inspirationHeight = _inspirationHeight(usableHeight);
          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: Column(
              children: [
                _topBar(),
                AnimatedContainer(
                  key: const Key('v2-intelligence-inspiration-stage'),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: inspirationHeight,
                  child: _InspirationStage(
                    snapshot: widget.snapshot,
                    notes: visibleNotes,
                    selectedNote: _selectedNote,
                    compact: inspirationHeight <= 190,
                    saved:
                        _selectedNote != null &&
                        _isSaved(library, _selectedNote!),
                    onSelect: _selectNote,
                    onShuffle: () => setState(() {
                      if (notes.isNotEmpty) {
                        _noteOffset = (_noteOffset + 5) % notes.length;
                      }
                    }),
                    onSave: _selectedNote == null
                        ? null
                        : () => _saveSelected(_selectedNote!),
                    onAction: _selectedNote == null
                        ? null
                        : () => _actOnNote(_selectedNote!),
                    onExpand: () {
                      _inputFocus.unfocus();
                      setState(() {});
                    },
                  ),
                ),
                Expanded(
                  child: _AssistantStage(
                    snapshot: widget.snapshot,
                    selectedNote: _selectedNote,
                    conversation: _conversation,
                    pendingIntent: _pendingIntent,
                    pendingText: _pendingText,
                    pendingSource: _pendingSource,
                    pendingPhase: _pendingPhase,
                    lastFailure: _lastFailure,
                    inputController: _inputController,
                    inputFocus: _inputFocus,
                    scrollController: _conversationScroll,
                    bottomSafe: bottomSafe,
                    onSubmit: _submitText,
                    onInputChanged: () => setState(() {}),
                    onSuggestion: _ask,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _topBar() => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _roundAction(
            icon: CupertinoIcons.xmark,
            label: '关闭栖光',
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/today');
              }
            },
          ),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '栖光',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  '灵感与对话',
                  style: TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _roundAction(
            icon: CupertinoIcons.square_pencil,
            label: '新建对话',
            onTap: _startNewConversation,
          ),
        ],
      ),
    ),
  );

  Widget _roundAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox.square(
        dimension: 40,
        child: Icon(icon, color: V2Palette.ink, size: 20),
      ),
    ),
  );

  double _inspirationHeight(double usableHeight) {
    switch (_layoutState) {
      case _IntelligenceLayoutState.typing:
        return usableHeight < 520 ? 92 : 104;
      case _IntelligenceLayoutState.conversation:
        return usableHeight < 600 ? 126 : 150;
      case _IntelligenceLayoutState.inspiration:
        return (usableHeight * .31).clamp(170.0, 238.0);
      case _IntelligenceLayoutState.home:
        if (usableHeight < 600) return 200;
        return (usableHeight * .29).clamp(210.0, 235.0);
    }
  }

  void _resolveInitialNote(List<InspirationNote> notes) {
    if (_initialNoteResolved) return;
    final requested = widget.initialNoteId;
    if (requested == null || requested.isEmpty) {
      _initialNoteResolved = true;
      return;
    }
    final note = notes.where((item) => item.id == requested).firstOrNull;
    if (note == null) return;
    _initialNoteResolved = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedNote == null) _selectNote(note);
    });
  }

  List<InspirationNote> _rotatedNotes(List<InspirationNote> notes) {
    if (notes.length <= 6) return notes;
    return List.generate(
      6,
      (index) => notes[(_noteOffset + index) % notes.length],
      growable: false,
    );
  }

  void _selectNote(InspirationNote note) {
    _inputFocus.unfocus();
    setState(() => _selectedNote = note);
    unawaited(_ask('请详细解读灵感「${note.label}」', note: note));
  }

  Future<void> _saveSelected(InspirationNote note) async {
    await ref
        .read(userLibraryProvider.notifier)
        .saveInspirationNote(snapshotId: widget.snapshot.id, note: note);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已收藏这张灵感')));
  }

  bool _isSaved(UserLibraryState? library, InspirationNote note) {
    final id = SavedInspirationNote.idFor(
      snapshotId: widget.snapshot.id,
      noteId: note.id,
    );
    return library?.savedNotes.any((item) => item.id == id) == true;
  }

  void _actOnNote(InspirationNote note) {
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

  void _submitText() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (text.length > 240) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('问题先缩到 240 字以内。')));
      return;
    }
    _inputController.clear();
    unawaited(_ask(text));
  }

  Future<void> _ask(String question, {InspirationNote? note}) async {
    final parsed = AssistantIntentParser.parse(question);
    if (parsed == null) return;
    final intent = parsed.type == AssistantQuestionType.general && note != null
        ? AssistantIntent(
            type: AssistantQuestionType.creative,
            normalizedQuestion: parsed.normalizedQuestion,
          )
        : parsed;
    final fallback = _localFallback(intent, note: note);
    final model = ref.read(assistantModelProvider);
    final canUseModel = model != null && intent.allowsRemoteRewrite;
    final generation = ++_generation;
    _cancelToken?.cancel('superseded');
    _cancelToken = null;

    setState(() {
      _lastFailure = null;
      _pendingIntent = intent;
      _pendingText = canUseModel ? '' : fallback;
      _pendingSource = canUseModel ? 'model' : 'template';
      _pendingPhase = canUseModel ? _PendingPhase.thinking : null;
    });
    _scheduleScroll();

    if (!canUseModel) {
      setState(() {
        _appendTurn(intent, fallback, 'template');
        _clearPending();
      });
      _scheduleScroll();
      return;
    }

    final token = CancelToken();
    _cancelToken = token;
    try {
      AssistantAnswer? completed;
      final preferences = ref.read(profilePreferencesProvider);
      final tone = NarrativeTone.values.byName(preferences.aiTone.name);
      await for (final event in model.answerStream(
        snapshot: widget.snapshot,
        surface: 'inspiration',
        intent: intent,
        eventIds: _assistantEventIds(note),
        tone: tone,
        conversationId: _conversation.id,
        history: _conversationHistory(),
        cancelToken: token,
      )) {
        if (!mounted || generation != _generation) return;
        switch (event) {
          case AssistantStreamThinking():
            setState(() => _pendingPhase = _PendingPhase.thinking);
          case AssistantStreamGenerating():
            setState(() => _pendingPhase = _PendingPhase.generating);
          case AssistantStreamDelta(:final text):
            setState(() {
              _pendingPhase = _PendingPhase.generating;
              _pendingText += text;
            });
          case AssistantStreamDone(:final answer):
            completed = answer;
        }
      }
      if (!mounted || generation != _generation) return;
      final answer = completed;
      if (answer == null) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      setState(() {
        _appendTurn(
          intent,
          answer.answer,
          answer.source.name,
          degradedReason: answer.degradedReason,
          webSources: answer.webSources,
        );
        _clearPending();
      });
      _scheduleScroll();
    } on AssistantFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _lastFailure = failure;
        _appendTurn(intent, fallback, 'template');
        _clearPending();
      });
      _scheduleScroll();
    }
  }

  List<String> _assistantEventIds(InspirationNote? note) {
    final ids = <String>{
      ...widget.snapshot.opportunityIds,
      ...widget.snapshot.safetyEventIds,
      ...widget.snapshot.wildlifeEventIds,
      ...widget.snapshot.events.map((item) => item.id),
      ...widget.snapshot.shootingSessions.map((item) => item.id),
      ?note?.opportunityId,
    };
    return ids.take(24).toList(growable: false);
  }

  List<AssistantHistoryTurn> _conversationHistory() {
    final values = <AssistantHistoryTurn>[
      for (final turn in _conversation.turns)
        if (turn.intent.normalizedQuestion.length <= 240 &&
            turn.answer.isNotEmpty &&
            turn.answer.length <= 200)
          AssistantHistoryTurn(
            question: turn.intent.normalizedQuestion,
            answer: turn.answer,
          ),
    ];
    return values.length <= assistantHistoryLimit
        ? values
        : values.sublist(values.length - assistantHistoryLimit);
  }

  void _appendTurn(
    AssistantIntent intent,
    String answer,
    String source, {
    String? degradedReason,
    List<AssistantWebSource> webSources = const [],
  }) {
    _conversation = _conversation.append(
      AssistantConversationTurn(
        id: '${_conversation.id}_${DateTime.now().microsecondsSinceEpoch}',
        intent: intent,
        answer: answer,
        source: source,
        createdAt: DateTime.now(),
        degradedReason: degradedReason,
        webSources: webSources,
      ),
    );
  }

  String _localFallback(AssistantIntent intent, {InspirationNote? note}) {
    final snapshot = widget.snapshot;
    final selected = note ?? _selectedNote;
    if (selected != null &&
        (note != null || intent.type == AssistantQuestionType.creative)) {
      final authority = selected.isFactual
          ? '这张纸条来自当前已成立的环境或拍摄事实。'
          : '这是一条创作提示，不代表现场条件一定成立。';
      return '${selected.detail}\n\n$authority\n'
          '${_creativeDirection(snapshot, selected)}';
    }

    final now = DateTime.now().toUtc();
    final session = ShootingSessionSelector.select(
      snapshot.shootingSessions.where((item) => !item.isEvidenceExpiredAt(now)),
      now: now,
    );
    return switch (intent.type) {
      AssistantQuestionType.shootingPlan => _currentShootingAnswer(
        snapshot,
        session,
        now,
      ),
      AssistantQuestionType.timing when session != null =>
        '当前最接近的拍摄窗口是「${session.title}」，'
            '${_time(session.presentationStartsAt)}—'
            '${_time(session.presentationEndsAt)}。'
            '打开机会详情可以查看判断依据和出发动作。',
      AssistantQuestionType.prepare =>
        '先按当前天气准备基础防护，再根据具体题材决定镜头。'
            '${snapshot.windSpeedMetersPerSecond == null ? '' : ' 当前风速约${snapshot.windSpeedMetersPerSecond!.toStringAsFixed(1)} m/s。'}',
      AssistantQuestionType.safety =>
        snapshot.isStale
            ? '当前环境数据已经过期，不能据此作出出发决定。请先刷新天气和预警。'
            : '当前天气为${_weather(snapshot.weather)}。安全问题只依据确定性天气与预警，不由模型猜测。',
      AssistantQuestionType.nearby =>
        '附近地点需要结合地图、开放状态和实际绕行成本筛选。打开探索页后，栖光会以当前地点为起点继续判断。',
      _ =>
        '我正在参考${_scene(snapshot.primaryScene)}、${_weather(snapshot.weather)}、'
            '${snapshot.shootingSessions.length}条拍摄机会和当前路线状态。'
            '可以直接问拍什么、何时出发、沿途停哪里或需要带什么。',
    };
  }

  String _currentShootingAnswer(
    ContextSnapshot snapshot,
    ShootingSession? session,
    DateTime now,
  ) {
    if (snapshot.isStale || !snapshot.expiresAt.isAfter(now)) {
      return '当前环境数据已经过期，不能据此判断今天适合拍什么。请先刷新天气和预警。';
    }
    final facts = <String>['当前${_weather(snapshot.weather)}'];
    if (snapshot.windSpeedMetersPerSecond case final wind?) {
      facts.add('风速约${wind.toStringAsFixed(1)} m/s');
    }
    if (snapshot.visibilityKilometers case final visibility?) {
      facts.add('能见度约${visibility.toStringAsFixed(0)} km');
    }
    if (session == null) {
      return '${facts.join('，')}。当前没有仍有效的拍摄窗口，先观察现场光线变化。';
    }
    return '${facts.join('，')}。今天优先拍「${session.title}」，'
        '窗口为${_time(session.presentationStartsAt)}—'
        '${_time(session.presentationEndsAt)}；'
        '打开机会详情可查看依据和行动安排。';
  }

  String _creativeDirection(ContextSnapshot snapshot, InspirationNote note) {
    final weather = _weather(snapshot.weather);
    final scene = _scene(snapshot.primaryScene);
    return '可以先围绕「${note.label}」观察$scene中的主体关系。'
        '当前是$weather条件，优先确认光线方向、前景和可安全停留的位置；'
        '需要具体机位时再进入探索地图。';
  }

  void _startNewConversation() {
    _generation += 1;
    _cancelToken?.cancel('new_conversation');
    _cancelToken = null;
    _inputController.clear();
    _inputFocus.unfocus();
    setState(() {
      _conversation = AssistantConversationState(id: _newConversationId());
      _selectedNote = null;
      _lastFailure = null;
      _clearPending();
    });
  }

  void _clearPending() {
    _pendingIntent = null;
    _pendingText = '';
    _pendingSource = null;
    _pendingPhase = null;
  }

  String _newConversationId() =>
      'intelligence_${widget.snapshot.id}_${DateTime.now().microsecondsSinceEpoch}';

  void _scheduleScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_conversationScroll.hasClients) return;
      unawaited(
        _conversationScroll.animateTo(
          _conversationScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _weather(WeatherType value) => switch (value) {
    WeatherType.clear => '晴朗',
    WeatherType.cloudy => '多云',
    WeatherType.rain => '有雨',
    WeatherType.snow => '有雪',
    WeatherType.dust => '扬尘',
    WeatherType.unknown => '未知天气',
  };

  static String _scene(SceneType value) => switch (value) {
    SceneType.city => '城市',
    SceneType.lake => '湖泊',
    SceneType.mountain => '山地',
    SceneType.desert => '荒漠',
    SceneType.village => '村镇',
    SceneType.unknown => '当前区域',
  };
}

class _InspirationStage extends StatelessWidget {
  const _InspirationStage({
    required this.snapshot,
    required this.notes,
    required this.selectedNote,
    required this.compact,
    required this.saved,
    required this.onSelect,
    required this.onShuffle,
    required this.onSave,
    required this.onAction,
    required this.onExpand,
  });

  final ContextSnapshot snapshot;
  final List<InspirationNote> notes;
  final InspirationNote? selectedNote;
  final bool compact;
  final bool saved;
  final ValueChanged<InspirationNote> onSelect;
  final VoidCallback onShuffle;
  final VoidCallback? onSave;
  final VoidCallback? onAction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(compact ? 24 : 32),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE6EEE7), Color(0xFFF2E9DD)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .9)),
      boxShadow: [
        BoxShadow(
          color: V2Palette.ink.withValues(alpha: .09),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: compact ? _compact(context) : _expanded(context),
  );

  Widget _compact(BuildContext context) {
    final note = selectedNote;
    return InkWell(
      key: const Key('v2-intelligence-compact-inspiration'),
      onTap: onExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .72),
                shape: BoxShape.circle,
              ),
              child: Text(
                note?.emoji ?? '✦',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note?.label ?? '此刻灵感',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: V2Palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note == null ? '输入时收拢，灵感上下文仍会保留' : note.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: V2Palette.mutedInk,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_down, color: V2Palette.moss),
          ],
        ),
      ),
    );
  }

  Widget _expanded(BuildContext context) {
    final note = selectedNote;
    final visibleNotes = notes.take(3).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '此刻灵感',
                style: TextStyle(
                  color: V2Palette.moss,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onShuffle,
                icon: const Icon(CupertinoIcons.shuffle, size: 15),
                label: const Text('换一组'),
                style: TextButton.styleFrom(foregroundColor: V2Palette.ink),
              ),
            ],
          ),
          if (note == null) ...[
            const SizedBox(height: 8),
            Wrap(
              key: const Key('v2-intelligence-inspiration-rail'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < visibleNotes.length; index++)
                  _V2InspirationNoteAction(
                    key: Key('v2-intelligence-note-$index'),
                    item: visibleNotes[index],
                    onTap: () => onSelect(visibleNotes[index]),
                  ),
              ],
            ),
          ] else ...[
            Expanded(
              key: const Key('v2-intelligence-selected-note'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .68),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      note.emoji,
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: V2Palette.ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          note.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: V2Palette.mutedInk,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onSave,
                  icon: Icon(
                    saved
                        ? CupertinoIcons.bookmark_fill
                        : CupertinoIcons.bookmark,
                    size: 16,
                  ),
                  label: Text(saved ? '已收藏' : '收藏'),
                ),
                const Spacer(),
                if (onAction != null)
                  FilledButton.tonalIcon(
                    onPressed: onAction,
                    icon: const Icon(CupertinoIcons.arrow_up_right, size: 15),
                    label: const Text('相关内容'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _V2InspirationNoteAction extends StatelessWidget {
  const _V2InspirationNoteAction({
    super.key,
    required this.item,
    required this.onTap,
  });

  final InspirationNote item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '查看灵感：${item.label}',
    child: Material(
      color: Colors.white.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.emoji),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AssistantStage extends StatelessWidget {
  const _AssistantStage({
    required this.snapshot,
    required this.selectedNote,
    required this.conversation,
    required this.pendingIntent,
    required this.pendingText,
    required this.pendingSource,
    required this.pendingPhase,
    required this.lastFailure,
    required this.inputController,
    required this.inputFocus,
    required this.scrollController,
    required this.bottomSafe,
    required this.onSubmit,
    required this.onInputChanged,
    required this.onSuggestion,
  });

  final ContextSnapshot snapshot;
  final InspirationNote? selectedNote;
  final AssistantConversationState conversation;
  final AssistantIntent? pendingIntent;
  final String pendingText;
  final String? pendingSource;
  final _PendingPhase? pendingPhase;
  final AssistantFailure? lastFailure;
  final TextEditingController inputController;
  final FocusNode inputFocus;
  final ScrollController scrollController;
  final double bottomSafe;
  final VoidCallback onSubmit;
  final VoidCallback onInputChanged;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('v2-intelligence-assistant-stage'),
    decoration: const BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    child: Column(
      children: [
        _contextStrip(),
        Expanded(
          child: conversation.turns.isEmpty && pendingIntent == null
              ? _welcome()
              : _conversation(),
        ),
        _composer(),
      ],
    ),
  );

  Widget _contextStrip() => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: V2Palette.line)),
    ),
    child: Row(
      children: [
        const Icon(CupertinoIcons.scope, color: V2Palette.moss, size: 15),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            selectedNote == null
                ? '正在参考当前环境 · ${snapshot.shootingSessions.length} 条拍摄机会'
                : '正在参考「${selectedNote!.label}」· 当前环境 · 拍摄机会',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _welcome() {
    final suggestions = selectedNote == null
        ? const ['今天适合拍什么？', '什么时候出发？', '需要带什么器材？', '沿途哪里值得停？']
        : ['这个灵感怎么拍？', '附近哪里适合？', '需要什么器材？', '换一种构图思路'];
    return ListView(
      key: const Key('v2-intelligence-empty-conversation'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                decoration: BoxDecoration(
                  color: V2Palette.canvas,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(5),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: V2Palette.line),
                ),
                child: const Text(
                  '直接问我想拍什么、准备去哪，或从上方抽一张灵感。',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in suggestions)
              ActionChip(
                label: Text(item),
                onPressed: () => onSuggestion(item),
                backgroundColor: V2Palette.mossSoft,
                side: const BorderSide(color: V2Palette.line),
                labelStyle: const TextStyle(
                  color: V2Palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _conversation() => ListView(
    controller: scrollController,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    children: [
      for (final turn in conversation.turns) _turn(turn),
      if (pendingIntent != null)
        _pendingTurn(
          intent: pendingIntent!,
          text: pendingText,
          phase: pendingPhase,
        ),
      if (lastFailure != null)
        const Padding(
          padding: EdgeInsets.only(left: 39, bottom: 10),
          child: Text(
            '模型暂时不可用，已保留基于当前数据的回答。',
            style: TextStyle(color: V2Palette.mutedInk, fontSize: 10.5),
          ),
        ),
    ],
  );

  Widget _turn(AssistantConversationTurn turn) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: .84,
            child: Container(
              key: const Key('v2-intelligence-user-message'),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: const BoxDecoration(
                color: V2Palette.skySoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(5),
                ),
              ),
              child: Text(
                turn.intent.normalizedQuestion,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        _assistantBubble(
          text: turn.answer,
          source: turn.source,
          webSources: turn.webSources,
        ),
      ],
    ),
  );

  Widget _pendingTurn({
    required AssistantIntent intent,
    required String text,
    required _PendingPhase? phase,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: .84,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: const BoxDecoration(
                color: V2Palette.skySoft,
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Text(intent.normalizedQuestion),
            ),
          ),
        ),
        const SizedBox(height: 9),
        _assistantBubble(
          text: text.isEmpty ? '正在整理当前上下文…' : text,
          source: switch (phase) {
            _PendingPhase.thinking => '正在思考',
            _PendingPhase.generating => '正在生成',
            null => pendingSource ?? '正在整理',
          },
          loading: true,
        ),
      ],
    ),
  );

  Widget _assistantBubble({
    required String text,
    required String source,
    List<AssistantWebSource> webSources = const [],
    bool loading = false,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _avatar(),
      const SizedBox(width: 9),
      Expanded(
        child: Container(
          key: const Key('v2-intelligence-assistant-message'),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: V2Palette.canvas,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: V2Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  if (loading) ...[
                    const SizedBox.square(
                      dimension: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.4,
                        color: V2Palette.moss,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    source == 'model'
                        ? '栖光模型 · 已参考当前上下文'
                        : source == 'template'
                        ? '栖光规则 · 当前数据'
                        : source,
                    style: const TextStyle(
                      color: V2Palette.mutedInk,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (webSources.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in webSources)
                      ActionChip(
                        label: Text('来源 · ${item.publisher}'),
                        onPressed: () => launchUrl(
                          item.url,
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );

  Widget _avatar() => Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: V2Palette.mossSoft,
      shape: BoxShape.circle,
    ),
    child: const Icon(CupertinoIcons.sparkles, color: V2Palette.moss, size: 15),
  );

  Widget _composer() {
    final canSend = inputController.text.trim().isNotEmpty;
    return Container(
      key: const Key('v2-intelligence-composer'),
      padding: EdgeInsets.fromLTRB(16, 9, 16, 10 + bottomSafe),
      decoration: const BoxDecoration(
        color: V2Palette.paper,
        border: Border(top: BorderSide(color: V2Palette.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              decoration: BoxDecoration(
                color: V2Palette.canvas,
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                key: const Key('v2-intelligence-input'),
                controller: inputController,
                focusNode: inputFocus,
                textInputAction: TextInputAction.send,
                onChanged: (_) => onInputChanged(),
                onSubmitted: (_) => onSubmit(),
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 15,
                  height: 1.35,
                ),
                decoration: const InputDecoration(
                  hintText: '直接问栖光…',
                  hintStyle: TextStyle(color: V2Palette.mutedInk),
                  filled: true,
                  fillColor: V2Palette.canvas,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('v2-intelligence-send'),
            tooltip: '发送',
            onPressed: canSend ? onSubmit : null,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(46),
              maximumSize: const Size.square(46),
              padding: EdgeInsets.zero,
              backgroundColor: V2Palette.moss,
              foregroundColor: Colors.white,
              disabledBackgroundColor: V2Palette.canvas,
              disabledForegroundColor: V2Palette.line,
            ),
            icon: const Icon(CupertinoIcons.arrow_up, size: 20),
          ),
        ],
      ),
    );
  }
}
