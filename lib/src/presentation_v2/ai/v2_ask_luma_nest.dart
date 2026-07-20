import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/assistant/assistant_model.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

enum _AskQuestion { why, prepare, wording, nearby, timing, creative, safety }

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
  builder: (_) => _AskLumaNestSheet(
    snapshot: snapshot,
    session: session,
    judgement: judgement,
    eventIds: eventIds,
    places: places,
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
      padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.sparkles, size: 15, color: V2Palette.moss),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
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
  final Iterable<String> eventIds;
  final Iterable<NearbyPlace> places;
  final String surface;
  final String? initialQuestion;

  @override
  ConsumerState<_AskLumaNestSheet> createState() => _AskLumaNestSheetState();
}

class _AskLumaNestSheetState extends ConsumerState<_AskLumaNestSheet> {
  _AskQuestion? _selected;
  Future<AssistantAnswer?>? _remoteAnswer;
  bool _hasFollowUp = false;
  final _inputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuestion?.trim();
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputController.text = initial;
          _submitFreeText();
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answer = _selected == null ? null : _answer(_selected!);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitFreeText(),
                    decoration: const InputDecoration(
                      hintText: '也可以直接问一句',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                V2Pressable(
                  onTap: _submitFreeText,
                  compact: true,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Text(
                      '问',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final question in _availableQuestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: V2Pressable(
                  onTap: () {
                    setState(() {
                      _selected = question;
                      _remoteAnswer = _request(question);
                    });
                  },
                  color: _selected == question
                      ? V2Palette.mossSoft
                      : V2Palette.paper,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 13,
                    ),
                    child: Text(
                      _questionLabel(question),
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            if (answer != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: V2Palette.night,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: FutureBuilder<AssistantAnswer?>(
                  future: _remoteAnswer,
                  builder: (context, snapshot) {
                    final resolved = snapshot.data;
                    final displayed = resolved?.answer ?? answer;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          displayed,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.45,
                            fontSize: 15,
                          ),
                        ),
                        if (snapshot.connectionState ==
                            ConnectionState.done) ...[
                          const SizedBox(height: 10),
                          Text(
                            _sourceLabel(
                              resolved?.source ?? 'template',
                              question: _selected,
                            ),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .68),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (_hasFollowUp) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _inputController,
                            style: const TextStyle(color: Colors.white),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _submitFollowUp(),
                            decoration: InputDecoration(
                              hintText: '继续问一件事',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: .55),
                              ),
                              suffixIcon: IconButton(
                                onPressed: _submitFollowUp,
                                icon: const Icon(
                                  CupertinoIcons.arrow_up_circle_fill,
                                  color: Colors.white,
                                ),
                              ),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: .28),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<AssistantAnswer?> _request(_AskQuestion question) async {
    final model = ref.read(assistantModelProvider);
    if (model == null) return null;
    try {
      final result = await model.answer(
        snapshot: widget.snapshot,
        surface: widget.surface,
        questionType: question.name,
        eventIds: widget.eventIds.toList(growable: false),
        tone: NarrativeTone.balanced,
        places: widget.places,
      );
      if (mounted) setState(() => _hasFollowUp = true);
      return result;
    } catch (_) {
      return null;
    }
  }

  void _submitFreeText() {
    final question = _classify(_inputController.text);
    if (question == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('先问拍摄依据、时间、器材或附近地点')));
      return;
    }
    _selectQuestion(question);
  }

  void _submitFollowUp() {
    final question = _classify(_inputController.text);
    if (question == null) return;
    _inputController.clear();
    _selectQuestion(question);
  }

  void _selectQuestion(_AskQuestion question) {
    setState(() {
      _selected = question;
      _remoteAnswer = _request(question);
    });
  }

  _AskQuestion? _classify(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (RegExp(r'安全|危险|雷|风|雨|能不能去|适合出门|能出门|适合拍|可以去吗|天气').hasMatch(text)) {
      return _AskQuestion.safety;
    }
    if (RegExp(r'附近|哪里|地点|活动|机位|值得去|推荐|去哪|什么地方|周边').hasMatch(text)) {
      return _AskQuestion.nearby;
    }
    if (RegExp(r'怎么拍|拍法|构图|取景|参数|创作|具体拍|变成照片').hasMatch(text)) {
      return _AskQuestion.creative;
    }
    if (RegExp(r'几点|时间|什么时候|出发|到达|窗口|多久|几点去|现在去').hasMatch(text)) {
      return _AskQuestion.timing;
    }
    if (RegExp(r'带什么|器材|装备|准备|穿什么|需要带').hasMatch(text)) {
      return _AskQuestion.prepare;
    }
    if (RegExp(r'为什么|依据|原因|条件|怎么判断|凭什么').hasMatch(text)) {
      return _AskQuestion.why;
    }
    if (RegExp(r'简洁|换个说法|总结|怎么说|简单说|短一点').hasMatch(text)) {
      return _AskQuestion.wording;
    }
    return null;
  }

  String _questionLabel(_AskQuestion question) => switch (question) {
    _AskQuestion.why => '为什么是这个窗口？',
    _AskQuestion.prepare => '需要带什么？',
    _AskQuestion.wording => '换一种更简洁的说法',
    _AskQuestion.nearby => '附近有什么值得去？',
    _AskQuestion.timing => '这个窗口什么时候？',
    _AskQuestion.creative => '把这个灵感变成具体拍法',
    _AskQuestion.safety => '当前有什么安全提醒？',
  };

  String get _subtitle => switch (widget.surface) {
    'explore' => '只看附近候选，不把候选地点说成已审核机位。',
    'inspiration' => '只展开已有灵感，不新增地点、机会或风险。',
    'shootingWindow' => '只根据这个窗口已经成立的依据回答。',
    _ => '只根据此刻已经成立的判断回答。',
  };

  List<_AskQuestion> get _availableQuestions {
    final hasSafety = widget.snapshot.safetyEventIds.isNotEmpty;
    final questions = <_AskQuestion>[];
    if (widget.surface == 'explore' && widget.places.isNotEmpty) {
      questions.add(_AskQuestion.nearby);
    }
    if (widget.surface == 'inspiration') {
      questions.add(_AskQuestion.creative);
      if (widget.places.isNotEmpty) questions.add(_AskQuestion.nearby);
    }
    if (widget.session != null) {
      questions
        ..add(_AskQuestion.why)
        ..add(_AskQuestion.timing)
        ..add(_AskQuestion.prepare);
    } else if (widget.judgement?.trim().isNotEmpty == true) {
      questions
        ..add(_AskQuestion.why)
        ..add(_AskQuestion.wording);
    }
    if (hasSafety) questions.add(_AskQuestion.safety);
    if (questions.isEmpty && widget.surface == 'explore') {
      questions.add(_AskQuestion.nearby);
    }
    return questions.toSet().toList(growable: false);
  }

  String _sourceLabel(String source, {_AskQuestion? question}) =>
      switch (source) {
        'model' =>
          question == _AskQuestion.nearby ? '模型改写 · 基于附近候选' : '模型改写 · 基于当前情境',
        'template' =>
          question == _AskQuestion.nearby ? '本地模板 · 基于附近候选' : '本地模板 · 基于当前情境',
        _ => '基于当前情境',
      };

  String _answer(_AskQuestion question) {
    final session = widget.session;
    return switch (question) {
      _AskQuestion.why =>
        session == null
            ? (widget.judgement?.trim().isNotEmpty == true
                  ? widget.judgement!
                  : '当前没有独立的拍摄窗口，先看环境变化。')
            : _why(session),
      _AskQuestion.prepare =>
        session == null
            ? '先保持轻装，等一个已经成立的光线窗口。'
            : session.recommendedCapabilities.isEmpty
            ? '当前没有额外器材要求。'
            : '可以准备${session.recommendedCapabilities.map(_capability).join('、')}。',
      _AskQuestion.wording =>
        widget.judgement?.trim().isNotEmpty == true
            ? widget.judgement!.trim()
            : '先看时间，再决定是否出发。',
      _AskQuestion.nearby =>
        widget.places.isEmpty
            ? '附近暂时没有足够的地点资料，先移动地图范围再看。'
            : '当前附近可以先看${widget.places.take(3).map((place) => place.name).join('、')}。它们是候选地点，不等于已审核机位。',
      _AskQuestion.timing =>
        widget.session == null
            ? '当前没有可执行的拍摄时间窗口。'
            : '当前窗口是${_time(widget.session!.startsAt)}—${_time(widget.session!.endsAt)}，先看时间再决定是否出发。',
      _AskQuestion.creative =>
        widget.judgement?.trim().isNotEmpty == true
            ? '围绕「${widget.judgement!.trim()}」先确定一个主体，再用前景和光线方向组织画面。'
            : '先确定一个主体，再用前景和光线方向组织画面。',
      _AskQuestion.safety => '安全信息只看独立安全卡，不由模型改写。',
    };
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

  String _capability(Object value) => switch ('$value') {
    'EquipmentCapability.tripod' => '三脚架',
    'EquipmentCapability.wideAngle' => '广角镜头',
    'EquipmentCapability.telephoto' => '长焦镜头',
    'EquipmentCapability.filter' => '滤镜',
    'EquipmentCapability.weatherProtection' => '防雨装备',
    'EquipmentCapability.headlamp' => '头灯',
    _ => '常用器材',
  };

  String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}
