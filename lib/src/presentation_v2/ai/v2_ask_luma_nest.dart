import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/assistant/assistant_intent.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/photography/next_photography_window.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/application/nearby_candidate_ranker.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place_repository.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:url_launcher/url_launcher.dart';

/// Progress phase of a streaming assistant answer shown on the pending card.
enum _PendingPhase { thinking, generating }

Future<void> showAskLumaNestSheet(
  BuildContext context, {
  required ContextSnapshot snapshot,
  ShootingSession? session,
  String? judgement,
  Iterable<String> eventIds = const [],
  Iterable<NearbyPlace> places = const [],
  Iterable<InspirationNote> inspirationNotes = const [],
  String surface = 'today',
  String? initialQuestion,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  enableDrag: false,
  useSafeArea: false,
  backgroundColor: V2Palette.paper,
  builder: (_) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .995,
    child: _AskLumaNestSheet(
      snapshot: snapshot,
      session: session,
      judgement: judgement,
      eventIds: eventIds.toList(growable: false),
      places: places.toList(growable: false),
      inspirationNotes: inspirationNotes.toList(growable: false),
      surface: surface,
      initialQuestion: initialQuestion,
    ),
  ),
);

class AskLumaNestButton extends StatelessWidget {
  const AskLumaNestButton({super.key, required this.onTap, this.label = '问栖光'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    compact: true,
    semanticLabel: label,
    color: V2Palette.paper,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.sparkles, size: 15, color: V2Palette.moss),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AskLumaNestSheet extends ConsumerStatefulWidget {
  const _AskLumaNestSheet({
    required this.snapshot,
    required this.session,
    required this.judgement,
    required this.eventIds,
    required this.places,
    required this.inspirationNotes,
    required this.surface,
    this.initialQuestion,
  });

  final ContextSnapshot snapshot;
  final ShootingSession? session;
  final String? judgement;
  final List<String> eventIds;
  final List<NearbyPlace> places;
  final List<InspirationNote> inspirationNotes;
  final String surface;
  final String? initialQuestion;

  @override
  ConsumerState<_AskLumaNestSheet> createState() => _AskLumaNestSheetState();
}

class _AskLumaNestSheetState extends ConsumerState<_AskLumaNestSheet> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late AssistantConversationState _conversation;
  AssistantIntent? _pendingIntent;
  String? _pendingAnswer;
  String? _pendingSource;
  _PendingPhase? _pendingPhase;
  String? _pendingStreamedAnswer;
  AssistantFailure? _lastFailure;
  CancelToken? _cancelToken;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _conversation = AssistantConversationState(id: _newConversationId());
    final initial = widget.initialQuestion?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputController.text = initial;
        _submitText();
      });
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _cancelToken?.cancel('sheet_disposed');
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: V2Palette.paper,
      child: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: _conversation.turns.isEmpty && _pendingIntent == null
                  ? _welcome()
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      children: [
                        for (final turn in _conversation.turns)
                          _turnCard(
                            intent: turn.intent,
                            answer: turn.answer,
                            source: turn.source,
                            degradedReason: turn.degradedReason,
                            webSources: turn.webSources,
                          ),
                        if (_pendingIntent != null)
                          _turnCard(
                            intent: _pendingIntent!,
                            answer: _displayedPendingAnswer,
                            source: _pendingSource ?? 'template',
                            loading: true,
                            pendingPhase: _pendingPhase,
                          ),
                        if (_lastFailure != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _failureLabel(_lastFailure!),
                              style: const TextStyle(
                                color: V2Palette.mutedInk,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            _inputRow(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Container(
    height: 58,
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: V2Palette.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _roundIcon(
            icon: CupertinoIcons.xmark,
            label: '关闭',
            onTap: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '问栖光',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  '摄影对话',
                  style: TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _roundIcon(
            icon: CupertinoIcons.line_horizontal_3,
            label: '更多问题',
            onTap: _showQuestionMenu,
          ),
        ],
      ),
    ),
  );

  Widget _roundIcon({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: V2Palette.line.withValues(alpha: .55)),
        ),
        child: Icon(icon, color: V2Palette.ink, size: 20),
      ),
    ),
  );

  Widget _welcome() {
    final suggestions = <String>{
      '附近适合拍什么？',
      '什么时候出发？',
      '需要带什么器材？',
      '日出和银河去哪？',
      ...widget.inspirationNotes.map((note) => note.label),
    }.take(4).toList(growable: false);
    return ListView(
      key: const Key('v2-ai-empty-conversation'),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _assistantAvatar(),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
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
                  '你好，我是栖光。直接告诉我你想拍什么、准备去哪里，或者把眼前的问题发给我。',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(left: 39),
          child: Text(
            '可以这样问',
            style: TextStyle(
              color: V2Palette.mutedInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Padding(
          padding: const EdgeInsets.only(left: 39),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final label in suggestions) _recommendedPrompt(label),
            ],
          ),
        ),
      ],
    );
  }

  void _selectTopic(String topic) {
    final parsed = AssistantIntentParser.parse(topic);
    final intent =
        parsed != null && parsed.type != AssistantQuestionType.general
        ? parsed
        : AssistantIntent(
            type: AssistantQuestionType.creative,
            normalizedQuestion: topic,
          );
    _inputController.clear();
    _selectIntent(intent);
  }

  Widget _recommendedPrompt(String label) => InkWell(
    onTap: () => _selectTopic(label),
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: V2Palette.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: V2Palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(CupertinoIcons.arrow_up, color: V2Palette.moss, size: 13),
        ],
      ),
    ),
  );

  Widget _inputRow() {
    final canSend = _inputController.text.trim().isNotEmpty;
    return Container(
      key: const Key('v2-ai-composer'),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                controller: _inputController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitText(),
                onChanged: (_) => setState(() {}),
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 15,
                  height: 1.35,
                ),
                decoration: const InputDecoration(
                  hintText: '发消息给栖光',
                  hintStyle: TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
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
            key: const Key('v2-ai-send'),
            tooltip: '发送',
            onPressed: canSend ? _submitText : null,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(46),
              maximumSize: const Size.square(46),
              padding: EdgeInsets.zero,
              backgroundColor: V2Palette.moss,
              foregroundColor: V2Palette.paper,
              disabledBackgroundColor: V2Palette.canvas,
              disabledForegroundColor: V2Palette.line,
            ),
            icon: const Icon(CupertinoIcons.arrow_up, size: 20),
          ),
        ],
      ),
    );
  }

  void _showQuestionMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: V2Palette.paper,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(CupertinoIcons.square_pencil),
              title: const Text('新建对话'),
              onTap: () {
                Navigator.of(context).pop();
                _startNewConversation();
              },
            ),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              '选择一个方向',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final type in _availableQuestions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_questionLabel(type)),
                trailing: const Icon(CupertinoIcons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  _selectIntent(
                    AssistantIntent(
                      type: type,
                      normalizedQuestion: _questionLabel(type),
                      prefersConcise: type == AssistantQuestionType.wording,
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _turnCard({
    required AssistantIntent intent,
    required String answer,
    required String source,
    bool loading = false,
    String? degradedReason,
    List<AssistantWebSource> webSources = const [],
    _PendingPhase? pendingPhase,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: .82,
            child: Container(
              key: const Key('v2-ai-user-message'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: V2Palette.skySoft,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(5),
                ),
              ),
              child: Text(
                intent.normalizedQuestion,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _assistantAvatar(),
            const SizedBox(width: 9),
            Expanded(
              child: Container(
                key: const Key('v2-ai-assistant-message'),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
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
                      answer,
                      style: const TextStyle(
                        color: V2Palette.ink,
                        height: 1.5,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (loading) ...[
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: V2Palette.moss,
                            ),
                          ),
                          const SizedBox(width: 7),
                        ],
                        Expanded(
                          child: Text(
                            loading
                                ? _pendingLabel(pendingPhase)
                                : _sourceLabel(
                                    source,
                                    intent.type,
                                    degradedReason,
                                  ),
                            style: const TextStyle(
                              color: V2Palette.mutedInk,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (webSources.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final webSource in webSources)
                            InkWell(
                              onTap: () => launchUrl(
                                webSource.url,
                                mode: LaunchMode.externalApplication,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: V2Palette.paper,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: V2Palette.line),
                                ),
                                child: Text(
                                  '来源 · ${webSource.publisher}',
                                  style: const TextStyle(
                                    color: V2Palette.moss,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
        ),
      ],
    ),
  );

  Widget _assistantAvatar() => Container(
    width: 30,
    height: 30,
    decoration: const BoxDecoration(
      color: V2Palette.mossSoft,
      shape: BoxShape.circle,
    ),
    child: const Icon(CupertinoIcons.sparkles, color: V2Palette.moss, size: 15),
  );

  void _submitText() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (text.length > 240) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('问题有点长，先缩到 240 字以内吧。')));
      return;
    }
    final intent = AssistantIntentParser.parse(text);
    if (intent == null) return;
    _inputController.clear();
    _selectIntent(intent, allowLocalFallback: false);
  }

  Future<void> _selectIntent(
    AssistantIntent intent, {
    bool allowLocalFallback = true,
  }) async {
    _generation += 1;
    final generation = _generation;
    _cancelToken?.cancel('superseded');
    _cancelToken = null;
    if (intent.type == AssistantQuestionType.shootingPlan) {
      await _selectShootingPlan(intent, generation);
      return;
    }
    final localAnswer = _localAnswer(intent);
    final model = ref.read(assistantModelProvider);
    final deterministicOnly = !intent.allowsRemoteRewrite;
    final canUseModel = intent.allowsRemoteRewrite && model != null;

    setState(() {
      _lastFailure = null;
      _pendingIntent = canUseModel ? intent : null;
      _pendingAnswer = canUseModel
          ? (allowLocalFallback ? localAnswer : '')
          : null;
      _pendingSource = canUseModel ? 'template' : null;
      _pendingPhase = canUseModel ? _PendingPhase.thinking : null;
      _pendingStreamedAnswer = null;
      if (!canUseModel) {
        if (deterministicOnly || allowLocalFallback) {
          _appendTurn(intent, localAnswer, 'template');
        } else {
          _lastFailure = const AssistantFailure(
            AssistantFailureKind.unconfigured,
          );
          _appendTurn(intent, '这次没有生成回答，请稍后重试。', 'error');
        }
      }
    });
    if (!canUseModel) return;

    final logger = ref.read(appLoggerProvider);
    logger.info(
      LogCategory.aiCall,
      'assistant.started',
      data: const {LogDataKey.status: 'started', LogDataKey.source: 'manual'},
    );
    final token = CancelToken();
    _cancelToken = token;
    try {
      final stream = model.answerStream(
        snapshot: widget.snapshot,
        surface: widget.surface,
        intent: intent,
        eventIds: widget.eventIds,
        tone: intent.prefersConcise
            ? NarrativeTone.concise
            : NarrativeTone.balanced,
        conversationId: _conversation.id,
        history: _conversationHistory(),
        cancelToken: token,
      );
      AssistantAnswer? completedAnswer;
      await for (final event in stream) {
        if (!mounted || generation != _generation) return;
        switch (event) {
          case AssistantStreamThinking():
            setState(() => _pendingPhase = _PendingPhase.thinking);
          case AssistantStreamGenerating():
            setState(() => _pendingPhase = _PendingPhase.generating);
          case AssistantStreamDelta(:final text):
            setState(() {
              _pendingPhase = _PendingPhase.generating;
              _pendingStreamedAnswer = (_pendingStreamedAnswer ?? '') + text;
            });
          case AssistantStreamDone(:final answer):
            if (completedAnswer != null) {
              throw const AssistantFailure(
                AssistantFailureKind.invalidResponse,
              );
            }
            completedAnswer = answer;
        }
      }
      final answer = completedAnswer;
      if (answer == null) {
        throw const AssistantFailure(AssistantFailureKind.invalidResponse);
      }
      if (!allowLocalFallback &&
          answer.source == AssistantAnswerSource.template) {
        throw const AssistantFailure(AssistantFailureKind.unavailable);
      }
      if (!mounted || generation != _generation) return;
      final source = answer.source.name;
      setState(() {
        _clearPending();
        _appendTurn(
          intent,
          answer.answer,
          source,
          degradedReason: answer.degradedReason,
          webSources: answer.webSources,
        );
      });
      logger.info(
        LogCategory.aiCall,
        'assistant.completed',
        data: {LogDataKey.status: 'completed', LogDataKey.source: source},
      );
    } on AssistantFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _lastFailure = failure;
        _clearPending();
        if (allowLocalFallback) {
          _appendTurn(intent, localAnswer, 'template');
        } else {
          _appendTurn(intent, '这次没有生成回答，请稍后重试。', 'error');
        }
      });
      logger.warning(
        LogCategory.aiCall,
        'assistant.fallback',
        data: {
          LogDataKey.status: 'failed',
          LogDataKey.source: allowLocalFallback ? 'template' : 'none',
          LogDataKey.reason: _logReason(failure.kind),
        },
      );
    }
  }

  void _clearPending() {
    _pendingIntent = null;
    _pendingAnswer = null;
    _pendingSource = null;
    _pendingPhase = null;
    _pendingStreamedAnswer = null;
  }

  /// Starts a fresh conversation with a new id, cancelling any in-flight
  /// stream. Prior turns are dropped — the broker is stateless, so a new id
  /// simply means no history is attached to subsequent requests.
  void _startNewConversation() {
    _generation += 1;
    _cancelToken?.cancel('new_conversation');
    _cancelToken = null;
    setState(() {
      _conversation = AssistantConversationState(id: _newConversationId());
      _clearPending();
      _lastFailure = null;
    });
  }

  String _newConversationId() =>
      'conversation_${widget.snapshot.id}_${DateTime.now().microsecondsSinceEpoch}';

  /// Prior turns of the current conversation, bounded to the broker contract
  /// (≤8 turns, question ≤240, answer ≤200). Oversized local answers such as
  /// multi-line shooting plans are skipped so only verbatim-shown text is
  /// transported.
  List<AssistantHistoryTurn> _conversationHistory() {
    final turns = <AssistantHistoryTurn>[
      for (final turn in _conversation.turns)
        if (turn.intent.normalizedQuestion.isNotEmpty &&
            turn.intent.normalizedQuestion.length <= 240 &&
            turn.answer.isNotEmpty &&
            turn.answer.length <= 200)
          AssistantHistoryTurn(
            question: turn.intent.normalizedQuestion,
            answer: turn.answer,
          ),
    ];
    return turns.length <= assistantHistoryLimit
        ? turns
        : turns.sublist(turns.length - assistantHistoryLimit);
  }

  /// The pending card shows the streamed model text once deltas arrive, and
  /// falls back to the optimistic template preview before that.
  String get _displayedPendingAnswer {
    final streamed = _pendingStreamedAnswer;
    if (streamed != null && streamed.isNotEmpty) return streamed;
    return _pendingAnswer ?? '';
  }

  String _pendingLabel(_PendingPhase? phase) => switch (phase) {
    _PendingPhase.thinking => '正在思考',
    _PendingPhase.generating => '正在生成',
    null => '正在整理已成立的信息',
  };

  Future<void> _selectShootingPlan(
    AssistantIntent intent,
    int generation,
  ) async {
    setState(() {
      _lastFailure = null;
      _clearPending();
      _pendingIntent = intent;
      _pendingAnswer = '正在整理日出参考、夜空候选和驾车时间…';
      _pendingSource = 'plan';
    });
    final answer = await _shootingPlanAnswer();
    if (!mounted || generation != _generation) return;
    setState(() {
      _clearPending();
      _appendTurn(intent, answer, 'plan');
    });
  }

  Future<String> _shootingPlanAnswer() async {
    final snapshot = widget.snapshot;
    final origin = snapshot.location;
    if (origin == null) {
      return '还没有可用定位，无法给出附近日出或夜空候选。先选择当前位置或一个参考地点。';
    }
    final repository = ref.read(nearbyPlaceRepositoryProvider);
    final results = await Future.wait([
      _nearbyPlanCandidates(
        repository,
        origin: origin,
        category: NearbyPlaceCategory.sunriseCandidate,
      ),
      _nearbyPlanCandidates(
        repository,
        origin: origin,
        category: NearbyPlaceCategory.nightSkyCandidate,
      ),
    ]);
    final now = DateTime.now();
    final sunrise = _nextSunrise(snapshot, now);
    final night = NextPhotographyWindowResolver.resolve(
      snapshot: snapshot,
      now: now,
      nextSunrise: sunrise,
    );
    final lines = <String>[
      '日出',
      if (sunrise == null)
        '还没有下一次日出时间参考，刷新环境后再计算出发时间。'
      else
        '日出参考 ${_time(sunrise)}；以下按提前20分钟抵达倒推出发时间。',
      _candidateLines(results[0], sunrise: sunrise, now: now),
      '',
      '银河 / 夜空',
      if (night?.kind == NextPhotographyWindowKind.nightSky)
        '${night!.timeLabel}。${night.detail}'
      else
        '当前没有银河高度、光害和地平线依据，不能给出“适合拍银河”的确切时段；以下仅是夜空拍摄候选。',
      _candidateLines(results[1], sunrise: null, now: now),
      '',
      '地点均为附近候选，不等于已审核机位；出发前仍需确认目标地天气、开放与现场视野。',
    ];
    return lines.where((line) => line.isNotEmpty).join('\n');
  }

  Future<List<NearbyPlace>> _nearbyPlanCandidates(
    NearbyPlaceRepository repository, {
    required GeoPoint origin,
    required NearbyPlaceCategory category,
  }) async {
    final raw = await fetchOptionalNearbyPlaces(
      repository,
      center: origin,
      category: category,
      radiusMeters: 50000,
    );
    final shortlist = NearbyCandidateRanker.shortlist(
      raw,
      maximum: 4,
    ).take(2).toList(growable: false);
    final routed = await Future.wait(
      shortlist.map((place) async {
        try {
          final route = await ref
              .read(drivingRouteRepositoryProvider)
              .plan(
                DrivingRouteRequest(
                  origin: origin,
                  destination: place.point,
                  destinationName: place.name,
                ),
              );
          return place.copyWith(
            drivingDurationSeconds: route.durationSeconds,
            drivingDistanceMeters: route.distanceMeters,
          );
        } on Object {
          return place;
        }
      }),
    );
    return routed..sort((left, right) {
      final leftDuration = left.drivingDurationSeconds ?? 1 << 30;
      final rightDuration = right.drivingDurationSeconds ?? 1 << 30;
      return leftDuration == rightDuration
          ? left.distanceMeters.compareTo(right.distanceMeters)
          : leftDuration.compareTo(rightDuration);
    });
  }

  String _candidateLines(
    List<NearbyPlace> places, {
    required DateTime? sunrise,
    required DateTime now,
  }) {
    if (places.isEmpty) return '附近暂未查到足够的候选。';
    return places
        .map((place) {
          final duration = place.drivingDurationSeconds;
          if (duration == null) {
            return '• ${place.name} · 约${_distance(place.distanceMeters)}，需在地图确认驾车时间。';
          }
          final travel = _duration(duration);
          if (sunrise == null) return '• ${place.name} · 驾车$travel。';
          final departAt = sunrise.subtract(
            Duration(seconds: duration + 20 * 60),
          );
          if (!departAt.isAfter(now)) {
            return '• ${place.name} · 驾车$travel；按提前20分钟抵达计算已来不及。';
          }
          return '• ${place.name} · 驾车$travel，建议${_time(departAt)}出发。';
        })
        .join('\n');
  }

  DateTime? _nextSunrise(ContextSnapshot snapshot, DateTime now) {
    final candidates = <DateTime>[
      ...(snapshot.sunrise == null
          ? const <DateTime>[]
          : <DateTime>[snapshot.sunrise!]),
      for (final session in snapshot.shootingSessions)
        for (final phase in session.phases)
          if (phase.kind == ShootingPhaseKind.sunrise) phase.peaksAt,
    ]..sort();
    for (final candidate in candidates) {
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
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
        id: 'turn_${DateTime.now().microsecondsSinceEpoch}',
        intent: intent,
        answer: answer,
        source: source,
        degradedReason: degradedReason,
        webSources: webSources,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _localAnswer(AssistantIntent intent) {
    final session = widget.session;
    return switch (intent.type) {
      AssistantQuestionType.general => '这次没有生成回答，请稍后重试。',
      AssistantQuestionType.shootingPlan => '正在整理日出与夜空候选。',
      AssistantQuestionType.why =>
        session == null
            ? (widget.judgement?.trim().isNotEmpty == true
                  ? widget.judgement!.trim()
                  : '当前没有独立的拍摄窗口，先看环境变化。')
            : _why(session),
      AssistantQuestionType.prepare => _preparationAnswer(intent, session),
      AssistantQuestionType.wording =>
        widget.judgement?.trim().isNotEmpty == true
            ? widget.judgement!.trim()
            : '先看时间，再决定是否出发。',
      AssistantQuestionType.nearby =>
        widget.places.isEmpty
            ? '附近暂时没有足够的地点资料，先移动地图范围再看。'
            : '当前附近可以先看${widget.places.take(3).map((place) => place.name).join('、')}。它们是候选地点，不等于已审核机位。',
      AssistantQuestionType.timing => _timingAnswer(intent, session),
      AssistantQuestionType.creative =>
        widget.judgement?.trim().isNotEmpty == true
            ? '围绕「${widget.judgement!.trim()}」先确定一个主体，再用前景和光线方向组织画面。'
            : '先确定一个主体，再用前景和光线方向组织画面。',
      AssistantQuestionType.safety => '安全信息只看独立安全卡和官方依据，不由模型生成或改写。',
    };
  }

  String _preparationAnswer(AssistantIntent intent, ShootingSession? session) {
    if (session == null) return '先保持轻装，等一个已经成立的光线窗口。';
    final capabilities = session.recommendedCapabilities
        .map(_capability)
        .toList();
    if (capabilities.isEmpty) return '当前没有额外器材要求。';
    final focused = _equipmentLabel(intent.equipmentFocus);
    if (focused != null && !capabilities.contains(focused)) {
      return '当前已成立的建议是${capabilities.join('、')}；现有依据没有要求$focused。';
    }
    return '可以准备${capabilities.join('、')}。';
  }

  String _timingAnswer(AssistantIntent intent, ShootingSession? session) {
    if (session == null) return '当前没有可执行的拍摄时间窗口。';
    final base = '当前窗口是${_time(session.startsAt)}—${_time(session.endsAt)}。';
    final available = intent.availableMinutes;
    if (available == null) return '$base先结合实际路程，再决定是否出发。';
    final untilStart = session.startsAt.difference(DateTime.now()).inMinutes;
    if (untilStart <= 0) return '$base窗口已经开始，你有$available分钟可用。';
    return '$base距离开始约$untilStart分钟；你有$available分钟可用，是否赶得上仍取决于实际路程。';
  }

  String _why(ShootingSession session) {
    final factors = session.factors
        .where((factor) => factor.effect.name == 'supporting')
        .take(2)
        .map((factor) => '${factor.label}${factor.value}')
        .join('、');
    if (factors.isEmpty) return '这个窗口仍需现场观察，不建议只凭它出发。';
    return '主要依据是$factors；时间轴仍会随新环境数据更新。';
  }

  List<AssistantQuestionType> get _availableQuestions {
    final hasSafety = widget.snapshot.safetyEventIds.isNotEmpty;
    final questions = <AssistantQuestionType>[];
    if (widget.snapshot.location != null) {
      questions.add(AssistantQuestionType.shootingPlan);
    }
    if (widget.surface == 'explore') {
      questions.add(AssistantQuestionType.nearby);
    }
    if (widget.surface == 'inspiration') {
      questions.add(AssistantQuestionType.creative);
      if (widget.places.isNotEmpty) questions.add(AssistantQuestionType.nearby);
    }
    if (widget.session != null) {
      questions
        ..add(AssistantQuestionType.why)
        ..add(AssistantQuestionType.timing)
        ..add(AssistantQuestionType.prepare);
    } else if (widget.judgement?.trim().isNotEmpty == true) {
      questions
        ..add(AssistantQuestionType.why)
        ..add(AssistantQuestionType.wording);
    }
    if (hasSafety) questions.add(AssistantQuestionType.safety);
    if (questions.isEmpty) questions.add(AssistantQuestionType.wording);
    return questions.toSet().take(6).toList(growable: false);
  }

  String _questionLabel(AssistantQuestionType type) => switch (type) {
    AssistantQuestionType.general => '自由提问',
    AssistantQuestionType.shootingPlan => '日出和银河去哪？',
    AssistantQuestionType.why => '为什么是这个窗口？',
    AssistantQuestionType.prepare => '需要带什么？',
    AssistantQuestionType.wording => '简洁说一下',
    AssistantQuestionType.nearby => '附近有什么？',
    AssistantQuestionType.timing => '窗口什么时候？',
    AssistantQuestionType.creative => '怎么具体拍？',
    AssistantQuestionType.safety => '有什么安全提醒？',
  };

  String _sourceLabel(
    String source,
    AssistantQuestionType type,
    String? degradedReason,
  ) {
    if (type == AssistantQuestionType.shootingPlan) {
      return '日出参考 + 实际路线 + 夜空候选 · 未调用模型';
    }
    if (type == AssistantQuestionType.safety) return '本地安全规则 · 未调用模型';
    if (type == AssistantQuestionType.nearby) return '本地附近候选 · 未调用模型';
    if (source == 'error') return '未生成回答 · 未使用本地文案替代';
    if (source == 'model') {
      return type == AssistantQuestionType.general
          ? 'AI回答 · 通用摄影知识，不代表实时环境事实'
          : '模型改写 · 内容由AI生成，仅供参考';
    }
    if (degradedReason == 'rate_limited') {
      return '本地模板 · 模型请求较多，已使用本地答案';
    }
    if (degradedReason != null) return '本地模板 · 模型未参与本次回答';
    return '本地模板 · 基于已验证情境';
  }

  String _failureLabel(AssistantFailure failure) => switch (failure.kind) {
    AssistantFailureKind.rateLimited => '模型请求较多，请稍后重试。',
    AssistantFailureKind.snapshotExpired => '当前情境已过期，刷新后再问。',
    AssistantFailureKind.timeout ||
    AssistantFailureKind.network => '网络未完成 AI 回答，请重试。',
    AssistantFailureKind.cancelled => '上一条请求已取消。',
    AssistantFailureKind.unconfigured => 'AI 模型尚未配置。',
    _ => '这次没有生成 AI 回答，请重试。',
  };

  String _logReason(AssistantFailureKind kind) => switch (kind) {
    AssistantFailureKind.unconfigured => 'modelUnavailable',
    AssistantFailureKind.snapshotExpired => 'staleSnapshot',
    AssistantFailureKind.invalidResponse => 'schemaValidation',
    AssistantFailureKind.network || AssistantFailureKind.timeout => 'network',
    _ => 'requestFailure',
  };

  String _capability(Object value) => switch ('$value') {
    'EquipmentCapability.tripod' => '三脚架',
    'EquipmentCapability.wideAngle' => '广角镜头',
    'EquipmentCapability.telephoto' => '长焦镜头',
    'EquipmentCapability.filter' => '滤镜',
    'EquipmentCapability.weatherProtection' => '防雨装备',
    'EquipmentCapability.headlamp' => '头灯',
    _ => '常用器材',
  };

  String? _equipmentLabel(AssistantEquipmentFocus focus) => switch (focus) {
    AssistantEquipmentFocus.none => null,
    AssistantEquipmentFocus.tripod => '三脚架',
    AssistantEquipmentFocus.wideAngle => '广角镜头',
    AssistantEquipmentFocus.telephoto => '长焦镜头',
    AssistantEquipmentFocus.filter => '滤镜',
    AssistantEquipmentFocus.weatherProtection => '防雨装备',
    AssistantEquipmentFocus.headlamp => '头灯',
  };

  String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';

  String _duration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes分钟';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours小时' : '$hours小时$remainder分钟';
  }

  String _distance(int meters) =>
      meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)}公里' : '$meters米';
}
