import 'package:flutter/foundation.dart';

/// The identity of one user-selected shooting opportunity while it moves
/// across Today, the opportunity detail and Route.
///
/// This is deliberately transient. It carries no route geometry, weather or
/// recommendation state; those remain owned by the current snapshot and Route
/// feature. Its only job is to prevent a later selector from silently
/// replacing the user's chosen session or reviewed target.
@immutable
class ActiveShootingIntent {
  ActiveShootingIntent({
    required this.sessionId,
    this.targetId,
    required DateTime createdAt,
  }) : createdAt = createdAt.toUtc();

  final String sessionId;
  final String? targetId;
  final DateTime createdAt;

  Map<String, String> get queryParameters {
    final result = <String, String>{
      'intentAt': createdAt.toIso8601String(),
    };
    final target = targetId;
    if (target != null) result['target'] = target;
    return result;
  }

  /// Reads only the optional identity query values. A plain session deep link
  /// remains a legacy route and returns null, while a target-bearing link
  /// becomes an explicit intent.
  static ActiveShootingIntent? fromQueryParameters({
    required String sessionId,
    String? targetId,
    String? createdAt,
  }) {
    final cleanTarget = targetId?.trim();
    final cleanCreatedAt = createdAt?.trim();
    if (cleanTarget == null &&
        (cleanCreatedAt == null || cleanCreatedAt.isEmpty)) {
      return null;
    }
    if (!_validSessionId(sessionId) ||
        cleanTarget != null && !_validTargetId(cleanTarget)) {
      return null;
    }
    final parsed = cleanCreatedAt == null || cleanCreatedAt.isEmpty
        ? DateTime.now().toUtc()
        : DateTime.tryParse(cleanCreatedAt)?.toUtc();
    if (parsed == null) return null;
    return ActiveShootingIntent(
      sessionId: sessionId,
      targetId: cleanTarget,
      createdAt: parsed,
    );
  }

  static bool _validSessionId(String value) =>
      _validTypedId(value, 'session');

  static bool _validTargetId(String value) =>
      _validTypedId(value, 'target');

  // Current contracts use typed, URL-safe stable IDs with several historical
  // separators: session_..., session...., session-... (and target variants).
  // Preserve those forms while rejecting untyped or path-like values.
  static bool _validTypedId(String value, String prefix) {
    if (value.length < prefix.length + 2 || value.length > 128) return false;
    if (!value.startsWith(prefix)) return false;
    final separatorIndex = prefix.length;
    final separator = value.codeUnitAt(separatorIndex);
    if (separator != 46 && // .
        separator != 95 && // _
        separator != 58 && // :
        separator != 45) { // -
      return false;
    }
    for (var index = separatorIndex + 1; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (_isAsciiAlphaNumeric(code) ||
          code == 46 || // .
          code == 95 || // _
          code == 58 || // :
          code == 45) { // -
        continue;
      }
      return false;
    }
    return true;
  }

  static bool _isAsciiAlphaNumeric(int code) =>
      code >= 48 && code <= 57 ||
      code >= 65 && code <= 90 ||
      code >= 97 && code <= 122;
}
