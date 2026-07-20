import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/assistant/assistant_intent.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

Future<void> showAskLumaNestSheet(
  BuildContext context, {
  required ContextSnapshot snapshot,
  ShootingSession? session,
  String? judgement,
  Iterable<String> eventIds = const [],
  Iterable<NearbyPlace> places = const [],
  String surface = 'today',
  String? initialQuestion,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  backgroundColor: V2Palette.canvas,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AskLumaNestSheet(
    snapshot: snapshot,
    session: session,
    judgement: judgement,
    eventIds: eventIds.toList(growable: false),
    places: places.toList(growable: false),
    surface: surface,
    initialQuestion: initialQuestion,
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
    required this.surface,
    this.initialQuestion,
  });

  final ContextSnapshot snapshot;
  final ShootingSession? session;
  final String? judgement;
  final List<String> eventIds;
  final List<NearbyPlace> places;
  final String surface;
  final String? initialQuestion;

  @override
  ConsumerState<_AskLumaNestSheet> createState() => _AskLumaNestSheetState();
}

class _AskLumaNestSheetState extends ConsumerState<_AskLumaNestSheet> {
  final _inputController = TextEditingController();
  late AssistantConversationState _conversation;
  AssistantIntent? _pendingIntent;
  String? _pendingAnswer;
  String? _pendingSource;
  AssistantFailure? _lastFailure;
  CancelToken? _cancelToken;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _conversation = AssistantConversationState(
      id: 'conversation_${widget.snapshot.id}_${DateTime.now().microsecondsSinceEpoch}',
    );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maximumHeight = MediaQuery.sizeOf(context).height * .82;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maximumHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          4,
          22,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '问栖光',
              style: TextStyle(
                color: V2Palette.ink,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _subtitle,
              style: const TextStyle(color: V2Palette.mutedInk, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              '模型只改写已经成立的答案；安全与附近地点不交给模型生成。',
              style: TextStyle(
                color: V2Palette.mutedInk.withValues(alpha: .82),
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            _inputRow(),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _availableQuestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final type = _availableQuestions[index];
                  return V2Pressable(
                    compact: true,
                    color: _pendingIntent?.type == type
                        ? V2Palette.mossSoft
                        : V2Palette.paper,
                    onTap: () => _selectIntent(
                      AssistantIntent(
                        type: type,
                        normalizedQuestion: _questionLabel(type),
                        prefersConcise: type == AssistantQuestionType.wording,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      child: Text(
                        _questionLabel(type),
                        style: const TextStyle(
                          color: V2Palette.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _conversation.turns.isEmpty && _pendingIntent == null
                  ? const Center(
                      child: Text(
                        '选择一个问题，或直接输入一句。',
                        style: TextStyle(color: V2Palette.mutedInk),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        for (final turn in _conversation.turns)
                          _turnCard(
                            intent: turn.intent,
                            answer: turn.answer,
                            source: turn.source,
                          ),
                        if (_pendingIntent != null && _pendingAnswer != null)
                          _turnCard(
                            intent: _pendingIntent!,
                            answer: _pendingAnswer!,
                            source: _pendingSource ?? 'template',
                            loading: true,
                          ),
                      ],
                    ),
            ),
            if (_lastFailure != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
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
    );
  }

  Widget _inputRow() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _inputController,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submitText(),
          decoration: const InputDecoration(
            hintText: '问拍摄依据、时间、器材或附近地点',
            isDense: true,
          ),
        ),
      ),
      const SizedBox(width: 8),
      V2Pressable(
        onTap: _submitText,
        compact: true,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text('问', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    ],
  );

  Widget _turnCard({
    required AssistantIntent intent,
    required String answer,
    required String source,
    bool loading = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: V2Palette.night,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            intent.normalizedQuestion,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            answer,
            style: const TextStyle(
              color: Colors.white,
              height: 1.45,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (loading) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  loading ? '正在整理已成立的信息' : _sourceLabel(source, intent.type),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .64),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _submitText() {
    final intent = AssistantIntentParser.parse(_inputController.text);
    if (intent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前先问拍摄依据、时间、器材、安全或附近地点')),
      );
      return;
    }
    _inputController.clear();
    _selectIntent(intent);
  }

  Future<void> _selectIntent(AssistantIntent intent) async {
    _generation += 1;
    final generation = _generation;
    _cancelToken?.cancel('superseded');
    _cancelToken = null;
    final localAnswer = _localAnswer(intent);
    final model = ref.read(assistantModelProvider);
    final canUseModel = intent.allowsRemoteRewrite && model != null;

    setState(() {
      _lastFailure = null;
      _pendingIntent = canUseModel ? intent : null;
      _pendingAnswer = canUseModel ? localAnswer : null;
      _pendingSource = canUseModel ? 'template' : null;
      if (!canUseModel) {
        _appendTurn(intent, localAnswer, 'template');
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
      final result = await model.answer(
        snapshot: widget.snapshot,
        surface: widget.surface,
        intent: intent,
        eventIds: widget.eventIds,
        tone: intent.prefersConcise
            ? NarrativeTone.concise
            : NarrativeTone.balanced,
        // Nearby answers never reach this branch. Other intents do not need
        // client-provided place names, so the broker receives no unverified POI.
        places: const [],
        cancelToken: token,
      );
      if (!mounted || generation != _generation) return;
      final source = result.source.name;
      setState(() {
        _pendingIntent = null;
        _pendingAnswer = null;
        _pendingSource = null;
        _appendTurn(intent, result.answer, source);
      });
      logger.info(
        LogCategory.aiCall,
        'assistant.completed',
        data: {
          LogDataKey.status: 'completed',
          LogDataKey.source: source,
        },
      );
    } on AssistantFailure catch (failure) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _lastFailure = failure;
        _pendingIntent = null;
        _pendingAnswer = null;
        _pendingSource = null;
        _appendTurn(intent, localAnswer, 'template');
      });
      logger.warning(
        LogCategory.aiCall,
        'assistant.fallback',
        data: {
          LogDataKey.status: 'failed',
          LogDataKey.source: 'template',
          LogDataKey.reason: _logReason(failure.kind),
        },
      );
    }
  }

  void _appendTurn(AssistantIntent intent, String answer, String source) {
    _conversation = _conversation.append(
      AssistantConversationTurn(
        id: 'turn_${DateTime.now().microsecondsSinceEpoch}',
        intent: intent,
        answer: answer,
        source: source,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  String _localAnswer(AssistantIntent intent) {
    final session = widget.session;
    return switch (intent.type) {
      AssistantQuestionType.why => session == null
          ? (widget.judgement?.trim().isNotEmpty == true
                ? widget.judgement!.trim()
                : '当前没有独立的拍摄窗口，先看环境变化。')
          : _why(session),
      AssistantQuestionType.prepare => _preparationAnswer(intent, session),
      AssistantQuestionType.wording =>
        widget.judgement?.trim().isNotEmpty == true
            ? widget.judgement!.trim()
            : '先看时间，再决定是否出发。',
      AssistantQuestionType.nearby => widget.places.isEmpty
          ? '附近暂时没有足够的地点资料，先移动地图范围再看。'
          : '当前附近可以先看${widget.places.take(3).map((place) => place.name).join('、')}。它们是候选地点，不等于已审核机位。',
      AssistantQuestionType.timing => _timingAnswer(intent, session),
      AssistantQuestionType.creative =>
        widget.judgement?.trim().isNotEmpty == true
            ? '围绕「${widget.judgement!.trim()}」先确定一个主体，再用前景和光线方向组织画面。'
            : '先确定一个主体，再用前景和光线方向组织画面。',
      AssistantQuestionType.safety =>
        '安全信息只看独立安全卡和官方依据，不由模型生成或改写。',
    };
  }

  String _preparationAnswer(
    AssistantIntent intent,
    ShootingSession? session,
  ) {
    if (session == null) return '先保持轻装，等一个已经成立的光线窗口。';
    final capabilities = session.recommendedCapabilities.map(_capability).toList();
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

  String get _subtitle => switch (widget.surface) {
    'explore' => '只看附近候选，不把候选地点说成已审核机位。',
    'inspiration' => '只展开已有灵感，不新增地点、机会或风险。',
    'shootingWindow' => '只根据这个窗口已经成立的依据回答。',
    _ => '只根据此刻已经成立的判断回答。',
  };

  List<AssistantQuestionType> get _availableQuestions {
    final hasSafety = widget.snapshot.safetyEventIds.isNotEmpty;
    final questions = <AssistantQuestionType>[];
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
    AssistantQuestionType.why => '为什么是这个窗口？',
    AssistantQuestionType.prepare => '需要带什么？',
    AssistantQuestionType.wording => '简洁说一下',
    AssistantQuestionType.nearby => '附近有什么？',
    AssistantQuestionType.timing => '窗口什么时候？',
    AssistantQuestionType.creative => '怎么具体拍？',
    AssistantQuestionType.safety => '有什么安全提醒？',
  };

  String _sourceLabel(String source, AssistantQuestionType type) {
    if (type == AssistantQuestionType.safety) return '本地安全规则 · 未调用模型';
    if (type == AssistantQuestionType.nearby) return '本地附近候选 · 未调用模型';
    return source == 'model'
        ? '模型改写 · 基于已验证情境'
        : '本地模板 · 基于已验证情境';
  }

  String _failureLabel(AssistantFailure failure) => switch (failure.kind) {
    AssistantFailureKind.rateLimited => '模型请求较多，已使用本地答案。',
    AssistantFailureKind.snapshotExpired => '当前情境已更新，已使用本地答案。',
    AssistantFailureKind.timeout || AssistantFailureKind.network =>
      '网络未完成模型改写，已使用本地答案。',
    AssistantFailureKind.cancelled => '上一条请求已取消。',
    _ => '模型未参与本次回答，已使用本地答案。',
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
}
