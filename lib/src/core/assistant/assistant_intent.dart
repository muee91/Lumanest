import 'package:flutter/foundation.dart';

enum AssistantQuestionType {
  why,
  prepare,
  wording,
  nearby,
  timing,
  creative,
  safety,
}

enum AssistantSurface { today, explore, inspiration, shootingWindow }

enum AssistantTransportMode { unknown, walking, driving }

enum AssistantEquipmentFocus {
  none,
  tripod,
  wideAngle,
  telephoto,
  filter,
  weatherProtection,
  headlamp,
}

@immutable
class AssistantIntent {
  const AssistantIntent({
    required this.type,
    required this.normalizedQuestion,
    this.availableMinutes,
    this.transportMode = AssistantTransportMode.unknown,
    this.equipmentFocus = AssistantEquipmentFocus.none,
    this.prefersConcise = false,
  });

  final AssistantQuestionType type;
  final String normalizedQuestion;
  final int? availableMinutes;
  final AssistantTransportMode transportMode;
  final AssistantEquipmentFocus equipmentFocus;
  final bool prefersConcise;

  /// Safety, nearby-place and locally constrained answers remain
  /// deterministic. The current broker contract has no fact fields for the
  /// user's available time, transport mode or requested equipment, so sending
  /// those turns to the model would silently discard the constraint.
  bool get allowsRemoteRewrite =>
      type != AssistantQuestionType.safety &&
      type != AssistantQuestionType.nearby &&
      availableMinutes == null &&
      transportMode == AssistantTransportMode.unknown &&
      equipmentFocus == AssistantEquipmentFocus.none;

  String get contextKey => [
    type.name,
    if (availableMinutes != null) 'minutes:$availableMinutes',
    if (transportMode != AssistantTransportMode.unknown)
      'transport:${transportMode.name}',
    if (equipmentFocus != AssistantEquipmentFocus.none)
      'equipment:${equipmentFocus.name}',
    if (prefersConcise) 'concise',
  ].join('|');
}

abstract final class AssistantIntentParser {
  static AssistantIntent? parse(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty || text.length > 240) return null;

    final type = _questionType(text);
    if (type == null) return null;
    return AssistantIntent(
      type: type,
      normalizedQuestion: text,
      availableMinutes: _availableMinutes(text),
      transportMode: _transportMode(text),
      equipmentFocus: _equipmentFocus(text),
      prefersConcise: RegExp(r'简洁|简短|短一点|一句话|直接说|总结').hasMatch(text),
    );
  }

  static AssistantQuestionType? _questionType(String text) {
    if (RegExp(r'安全|危险|雷暴|雷电|暴雨|大风|降雪|结冰|下雨|下雪|天气|预警|封路|禁入|能不能去|适合出门|能出门|可以去吗').hasMatch(text)) {
      return AssistantQuestionType.safety;
    }
    if (RegExp(r'附近|哪里|地点|活动|机位|值得去|推荐|去哪|什么地方|周边|湖|山|街巷|公园').hasMatch(text)) {
      return AssistantQuestionType.nearby;
    }
    if (RegExp(r'怎么拍|拍法|构图|取景|参数|创作|具体拍|变成照片|前景|主体').hasMatch(text)) {
      return AssistantQuestionType.creative;
    }
    if (RegExp(r'几点|时间|什么时候|出发|到达|窗口|多久|来得及|赶得上|现在去').hasMatch(text)) {
      return AssistantQuestionType.timing;
    }
    if (RegExp(r'带什么|器材|装备|准备|穿什么|需要带|镜头|三脚架|滤镜|头灯|防雨|防水').hasMatch(text)) {
      return AssistantQuestionType.prepare;
    }
    if (RegExp(r'为什么|依据|原因|条件|怎么判断|凭什么').hasMatch(text)) {
      return AssistantQuestionType.why;
    }
    if (RegExp(r'简洁|换个说法|总结|怎么说|简单说|短一点|一句话').hasMatch(text)) {
      return AssistantQuestionType.wording;
    }
    return null;
  }

  static int? _availableMinutes(String text) {
    final match = RegExp(r'(\d{1,3})\s*(?:分钟|分)').firstMatch(text);
    final value = match == null ? null : int.tryParse(match.group(1)!);
    if (value == null || value <= 0 || value > 720) return null;
    return value;
  }

  static AssistantTransportMode _transportMode(String text) {
    if (RegExp(r'开车|驾车|自驾|车程').hasMatch(text)) {
      return AssistantTransportMode.driving;
    }
    if (RegExp(r'步行|走路|徒步').hasMatch(text)) {
      return AssistantTransportMode.walking;
    }
    return AssistantTransportMode.unknown;
  }

  static AssistantEquipmentFocus _equipmentFocus(String text) {
    if (text.contains('三脚架')) return AssistantEquipmentFocus.tripod;
    if (RegExp(r'广角|超广').hasMatch(text)) return AssistantEquipmentFocus.wideAngle;
    if (RegExp(r'长焦|远摄').hasMatch(text)) return AssistantEquipmentFocus.telephoto;
    if (RegExp(r'滤镜|ND|CPL').hasMatch(text)) return AssistantEquipmentFocus.filter;
    if (RegExp(r'防雨|雨衣|防水').hasMatch(text)) {
      return AssistantEquipmentFocus.weatherProtection;
    }
    if (RegExp(r'头灯|手电').hasMatch(text)) return AssistantEquipmentFocus.headlamp;
    return AssistantEquipmentFocus.none;
  }
}

@immutable
class AssistantConversationTurn {
  const AssistantConversationTurn({
    required this.id,
    required this.intent,
    required this.answer,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final AssistantIntent intent;
  final String answer;
  final String source;
  final DateTime createdAt;
}

@immutable
class AssistantConversationState {
  const AssistantConversationState({
    required this.id,
    this.turns = const [],
  });

  final String id;
  final List<AssistantConversationTurn> turns;

  AssistantConversationTurn? get latest => turns.lastOrNull;

  AssistantConversationState append(AssistantConversationTurn turn) {
    final retained = turns.length < 7
        ? turns
        : turns.skip(turns.length - 7);
    return AssistantConversationState(
      id: id,
      turns: List.unmodifiable([...retained, turn]),
    );
  }
}
