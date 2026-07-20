import 'package:flutter/foundation.dart';

enum SliceFreshness { fresh, stale, expired }

@immutable
class StateSlice<T> {
  const StateSlice({
    required this.value,
    required this.revision,
    required this.observedAt,
    required this.expiresAt,
    required this.freshness,
    required this.sourceFingerprint,
  });

  final T value;
  final int revision;
  final DateTime observedAt;
  final DateTime expiresAt;
  final SliceFreshness freshness;
  final String sourceFingerprint;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());
}
