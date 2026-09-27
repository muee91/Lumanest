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

  static bool _validSessionId(String value) => _validId(value);

  static bool _validTargetId(String value) => _validId(value);

  // Session/target IDs come from more than one current contract surface:
  // production IDs may be hash-like while deterministic fixtures and legacy
  // deep links still use dotted identifiers such as session.water.evening.
  // Keep the accepted alphabet URL-safe and bounded instead of assuming one
  // server-side ID shape.
  static bool _validId(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}
}
).hasMatch(value);
}
