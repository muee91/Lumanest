import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/assistant/assistant_intent.dart';

void main() {
  test('parses timing constraints without turning them into a model fact', () {
    final intent = AssistantIntentParser.parse('我只有20分钟，开车还能赶上窗口吗？');

    expect(intent, isNotNull);
    expect(intent!.type, AssistantQuestionType.timing);
    expect(intent.availableMinutes, 20);
    expect(intent.transportMode, AssistantTransportMode.driving);
    expect(intent.allowsRemoteRewrite, isTrue);
  });

  test('keeps safety and nearby intents deterministic', () {
    final safety = AssistantIntentParser.parse('现在有雷雨，能不能去？');
    final nearby = AssistantIntentParser.parse('附近有什么适合拍照的湖？');

    expect(safety!.type, AssistantQuestionType.safety);
    expect(safety.allowsRemoteRewrite, isFalse);
    expect(nearby!.type, AssistantQuestionType.nearby);
    expect(nearby.allowsRemoteRewrite, isFalse);
  });

  test('extracts equipment focus and concise preference', () {
    final intent = AssistantIntentParser.parse('简单说，需要带长焦吗？');

    expect(intent!.type, AssistantQuestionType.prepare);
    expect(intent.equipmentFocus, AssistantEquipmentFocus.telephoto);
    expect(intent.prefersConcise, isTrue);
  });

  test('rejects empty, oversized and unrelated input', () {
    expect(AssistantIntentParser.parse(''), isNull);
    expect(AssistantIntentParser.parse('你好'), isNull);
    expect(AssistantIntentParser.parse('为什么${'很' * 250}'), isNull);
  });

  test('conversation keeps only the latest eight completed turns', () {
    var state = const AssistantConversationState(id: 'conversation');
    for (var index = 0; index < 10; index += 1) {
      state = state.append(
        AssistantConversationTurn(
          id: 'turn-$index',
          intent: const AssistantIntent(
            type: AssistantQuestionType.why,
            normalizedQuestion: '为什么？',
          ),
          answer: '$index',
          source: 'template',
          createdAt: DateTime.utc(2026, 7, 20, 0, index),
        ),
      );
    }

    expect(state.turns, hasLength(8));
    expect(state.turns.first.id, 'turn-2');
    expect(state.turns.last.id, 'turn-9');
  });
}
