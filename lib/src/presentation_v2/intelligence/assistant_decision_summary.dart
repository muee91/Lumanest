import 'package:flutter/cupertino.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

@immutable
class AssistantDecisionSummaryData {
  const AssistantDecisionSummaryData({
    required this.conclusion,
    this.keyPoints = const [],
    this.limitations = const [],
    this.nextAction,
  });

  final String conclusion;
  final List<String> keyPoints;
  final List<String> limitations;
  final String? nextAction;

  static final _labelPattern = RegExp(
    r'^(结论|判断|建议|依据|重点|原因|限制|注意|不确定性|下一步|行动)\s*[：:｜|]\s*(.+)$',
  );
  static final _decisionPattern = RegExp(
    r'不适合|适合|不值得|值得|优先|可以拍|可拍|不能|暂时没有|没有.{0,12}窗口|建议|先别|重点关注|需要现场确认',
  );
  static final _actionPattern = RegExp(
    r'^(?:请|先|打开|进入|刷新|重新|继续|观察|查看|准备|再确认|建议)|'
    r'(?:请|先|打开|进入|刷新|重新|继续|观察|查看|准备|再确认)',
  );
  static final _limitationPattern = RegExp(
    r'不能|不代表|仅|只|暂时|缺少|不足|过期|不确定|可能|仍需|需现场|'
    r'单一来源|候选|风险|无法',
  );

  factory AssistantDecisionSummaryData.parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return const AssistantDecisionSummaryData(conclusion: '正在整理当前信息');
    }

    String? conclusion;
    final keyPoints = <String>[];
    final limitations = <String>[];
    String? nextAction;
    final unlabeled = <String>[];

    for (final rawLine in normalized.split('\n')) {
      final line = _clean(rawLine);
      if (line.isEmpty) continue;
      final match = _labelPattern.firstMatch(line);
      if (match == null) {
        unlabeled.add(line);
        continue;
      }
      final label = match.group(1)!;
      final value = _clean(match.group(2)!);
      if (value.isEmpty) continue;
      switch (label) {
        case '结论':
        case '判断':
        case '建议':
          conclusion ??= value;
        case '依据':
        case '重点':
        case '原因':
          _addUnique(keyPoints, value, 3);
        case '限制':
        case '注意':
        case '不确定性':
          _addUnique(limitations, value, 2);
        case '下一步':
        case '行动':
          nextAction ??= value;
      }
    }

    final sentences = <String>[
      for (final line in unlabeled)
        ...RegExp(r'[^。！？!?；;\n]+[。！？!?；;]?')
            .allMatches(line)
            .map((match) => _clean(match.group(0)!))
            .where((value) => value.isNotEmpty),
    ];

    if (conclusion == null && sentences.isNotEmpty) {
      final decisionIndex = sentences.indexWhere(_decisionPattern.hasMatch);
      final index = decisionIndex < 0 ? 0 : decisionIndex;
      conclusion = sentences.removeAt(index);
    }

    for (final sentence in sentences) {
      if (nextAction == null && _actionPattern.hasMatch(sentence)) {
        nextAction = sentence;
      } else if (_limitationPattern.hasMatch(sentence)) {
        _addUnique(limitations, sentence, 2);
      } else {
        _addUnique(keyPoints, sentence, 3);
      }
    }

    return AssistantDecisionSummaryData(
      conclusion: conclusion ?? normalized,
      keyPoints: List.unmodifiable(keyPoints),
      limitations: List.unmodifiable(limitations),
      nextAction: nextAction,
    );
  }

  static String _clean(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^(?:[•·\-—–]\s*|\d+[.)、．]\s*)'), '')
      .trim();

  static void _addUnique(List<String> values, String value, int maximum) {
    if (values.length >= maximum || values.contains(value)) return;
    values.add(value);
  }
}

class AssistantDecisionSummary extends StatelessWidget {
  const AssistantDecisionSummary({
    required this.text,
    this.loading = false,
    super.key,
  });

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Text(
        text,
        style: const TextStyle(color: V2Palette.ink, fontSize: 14, height: 1.5),
      );
    }

    final summary = AssistantDecisionSummaryData.parse(text);
    return Semantics(
      container: true,
      label: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.conclusion,
            key: const Key('assistant-decision-conclusion'),
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 17,
              height: 1.32,
              fontWeight: FontWeight.w900,
              letterSpacing: -.25,
            ),
          ),
          if (summary.keyPoints.isNotEmpty) ...[
            const SizedBox(height: 11),
            const _SectionLabel(label: '重点'),
            const SizedBox(height: 5),
            Column(
              key: const Key('assistant-decision-key-points'),
              children: [
                for (final point in summary.keyPoints) _PointRow(text: point),
              ],
            ),
          ],
          if (summary.limitations.isNotEmpty) ...[
            const SizedBox(height: 9),
            Container(
              key: const Key('assistant-decision-limitations'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: V2Palette.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel(label: '限制'),
                  const SizedBox(height: 4),
                  for (final item in summary.limitations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: V2Palette.mutedInk,
                          fontSize: 12,
                          height: 1.42,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (summary.nextAction case final action?) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('assistant-decision-next-action'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: V2Palette.mossSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      CupertinoIcons.arrow_right_circle_fill,
                      color: V2Palette.moss,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      action,
                      style: const TextStyle(
                        color: V2Palette.ink,
                        fontSize: 12.5,
                        height: 1.42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: V2Palette.moss,
      fontSize: 10.5,
      fontWeight: FontWeight.w900,
      letterSpacing: .5,
    ),
  );
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(top: 7, right: 8),
          decoration: const BoxDecoration(
            color: V2Palette.moss,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: V2Palette.ink,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}
