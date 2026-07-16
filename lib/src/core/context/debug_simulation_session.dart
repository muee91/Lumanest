import 'dart:math';

import 'package:flutter/foundation.dart';

/// Ephemeral debug-only pairing code. It is never persisted or sent by a
/// release build, and contains no device or location identity.
abstract final class DebugSimulationSession {
  static final String id = _newId();

  static String? get headerValue => kDebugMode ? id : null;

  static String _newId() {
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
