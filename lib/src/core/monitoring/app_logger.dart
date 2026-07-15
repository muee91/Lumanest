import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity levels for structured application logging.
enum LogLevel { debug, info, warning, error }

typedef AppLogSink = void Function(LogRecord record);

/// A structured log record emitted by [AppLogger].
///
/// Records are intentionally immutable and serializable so they can be
/// forwarded to any future sink (file, remote service, etc.) without
/// leaking references to mutable state.
class LogRecord {
  const LogRecord({
    required this.level,
    required this.category,
    required this.event,
    required this.timestamp,
    this.data,
  });

  final LogLevel level;
  final LogCategory category;
  final String event;
  final DateTime timestamp;
  final Map<String, Object?>? data;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' ')
      ..write(level.name.toUpperCase().padRight(8))
      ..write('[')
      ..write(category.value)
      ..write('] ')
      ..write(event);
    final attached = data;
    if (attached != null && attached.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(attached);
    }
    return buffer.toString();
  }
}

enum LogCategory {
  contextSnapshot('context.snapshot'),
  contextCache('context.cache'),
  degradation('context.degradation'),
  manifest('manifest'),
  aiCall('ai.call'),
  error('error');

  const LogCategory(this.value);
  final String value;
}

abstract final class LogDataKey {
  static const status = 'status';
  static const source = 'source';
  static const freshness = 'freshness';
  static const reason = 'reason';
  static const scene = 'scene';
  static const tone = 'tone';
  static const eventCount = 'eventCount';
  static const safetyCount = 'safetyCount';
  static const cache = 'cache';

  static const values = {
    status,
    source,
    freshness,
    reason,
    scene,
    tone,
    eventCount,
    safetyCount,
    cache,
  };
}

/// Emits bounded structured lifecycle events without accepting application
/// payloads. Category, event and data are sanitized before reaching the sink.
class AppLogger {
  AppLogger({this.enabled = true, AppLogSink? sink, DateTime Function()? now})
    : _sink = sink ?? _developerSink,
      _now = now ?? DateTime.now;

  bool enabled;
  final AppLogSink _sink;
  final DateTime Function() _now;

  void debug(
    LogCategory category,
    String event, {
    Map<String, Object?>? data,
  }) => _emit(LogLevel.debug, category, event, data);

  void info(LogCategory category, String event, {Map<String, Object?>? data}) =>
      _emit(LogLevel.info, category, event, data);

  void warning(
    LogCategory category,
    String event, {
    Map<String, Object?>? data,
  }) => _emit(LogLevel.warning, category, event, data);

  void error(
    LogCategory category,
    String event, {
    Map<String, Object?>? data,
  }) => _emit(LogLevel.error, category, event, data);

  void _emit(
    LogLevel level,
    LogCategory category,
    String event,
    Map<String, Object?>? data,
  ) {
    if (!enabled) return;

    final record = LogRecord(
      level: level,
      category: category,
      event: _sanitizeEvent(event),
      timestamp: _now().toUtc(),
      data: _sanitizeData(data),
    );

    _sink(record);
  }

  static String _sanitizeEvent(String value) {
    final event = value.trim();
    if (event.length > 80 || !_eventPattern.hasMatch(event)) {
      return 'invalid_event';
    }
    return event;
  }

  static Map<String, Object?>? _sanitizeData(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) return null;
    final sanitized = <String, Object?>{};
    for (final entry in data.entries) {
      if (!LogDataKey.values.contains(entry.key)) continue;
      final value = entry.value;
      if (_countKeys.contains(entry.key) &&
          value is int &&
          value >= 0 &&
          value <= 10000) {
        sanitized[entry.key] = value;
      } else if (!_countKeys.contains(entry.key) &&
          value is String &&
          (_allowedStringValues[entry.key]?.contains(value) ?? false)) {
        sanitized[entry.key] = value;
      }
    }
    return sanitized.isEmpty ? null : Map.unmodifiable(sanitized);
  }

  static final _eventPattern = RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$');
  static const _countKeys = {LogDataKey.eventCount, LogDataKey.safetyCount};
  static const _allowedStringValues = <String, Set<String>>{
    LogDataKey.status: {'started', 'completed', 'ok', 'failed', 'invalid'},
    LogDataKey.source: {
      'automatic',
      'manual',
      'local',
      'broker',
      'model',
      'template',
      'cache',
    },
    LogDataKey.freshness: {'fresh', 'stale'},
    LogDataKey.reason: {
      'configMissing',
      'location',
      'weather',
      'configuration',
      'network',
      'response',
      'unsupportedContract',
      'staleSnapshot',
      'modelUnavailable',
      'noCreativeEvents',
      'schemaValidation',
      'requestFailure',
    },
    LogDataKey.scene: {
      'unknown',
      'city',
      'lake',
      'mountain',
      'desert',
      'village',
      'driving',
      'hiking',
    },
    LogDataKey.tone: {'concise', 'balanced', 'detailed'},
    LogDataKey.cache: {'hit', 'miss', 'inFlight'},
  };

  static void _developerSink(LogRecord record) {
    final dartLevel = switch (record.level) {
      LogLevel.debug => 500,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
    };

    developer.log(record.toString(), name: 'LumaNest', level: dartLevel);

    if (kDebugMode) {
      debugPrint(record.toString());
    }
  }
}

final appLoggerProvider = Provider<AppLogger>((ref) {
  return AppLogger(enabled: true);
});
