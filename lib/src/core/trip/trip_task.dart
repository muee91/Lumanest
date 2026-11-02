import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

/// The single user-facing task that connects planning, departure and field
/// work in 2.0. Route geometry, weather and shooting evidence remain owned by
/// their existing providers; this object only owns the user's intent and its
/// lifecycle.
enum TripTaskStage { planning, enRoute, field, completed, cancelled }

enum TripTravelMode { driving, walking }

enum TripTaskCommandType { start, enterField, complete, cancel }

@immutable
class TripTaskCommand {
  const TripTaskCommand(this.type);

  final TripTaskCommandType type;
}

abstract final class TripTaskCommandParser {
  static TripTaskCommand? parse(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty || text.length > 80) return null;
    if (RegExp(r'^(?:开始出发|现在出发|我出发了|出发)$').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.start);
    }
    if (RegExp(r'(?:我到了|已到达|进入现场|开启现场模式)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.enterField);
    }
    if (RegExp(r'(?:结束这次|完成这次|结束任务|完成任务)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.complete);
    }
    if (RegExp(r'(?:取消任务|停止这次|停止守候)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.cancel);
    }
    return null;
  }
}

@immutable
class TripTask {
  const TripTask({
    required this.id,
    required this.destinationName,
    required this.destination,
    required this.travelMode,
    required this.stage,
    required this.createdAt,
    this.startedAt,
    this.fieldEnteredAt,
    this.completedAt,
    this.sessionId,
    this.targetId,
  });

  final String id;
  final String destinationName;
  final GeoPoint destination;
  final TripTravelMode travelMode;
  final TripTaskStage stage;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? fieldEnteredAt;
  final DateTime? completedAt;
  final String? sessionId;
  final String? targetId;

  bool get isOpen =>
      stage != TripTaskStage.completed && stage != TripTaskStage.cancelled;

  bool get isEnRoute => stage == TripTaskStage.enRoute;

  bool get isInField => stage == TripTaskStage.field;

  TripTask start({DateTime? at}) {
    if (stage == TripTaskStage.enRoute) return this;
    _requireOpen('start');
    final now = (at ?? DateTime.now()).toUtc();
    return _copy(stage: TripTaskStage.enRoute, startedAt: startedAt ?? now);
  }

  /// Field mode can be entered from planning as well as en-route. This keeps
  /// the task honest when a user arrives without opening an external map.
  TripTask enterField({DateTime? at}) {
    if (stage == TripTaskStage.field) return this;
    _requireOpen('enterField');
    final now = (at ?? DateTime.now()).toUtc();
    return _copy(
      stage: TripTaskStage.field,
      startedAt: startedAt ?? now,
      fieldEnteredAt: fieldEnteredAt ?? now,
    );
  }

  TripTask complete({DateTime? at}) {
    if (stage == TripTaskStage.completed) return this;
    _requireOpen('complete');
    return _copy(
      stage: TripTaskStage.completed,
      completedAt: (at ?? DateTime.now()).toUtc(),
    );
  }

  TripTask cancel() {
    if (stage == TripTaskStage.cancelled) return this;
    _requireOpen('cancel');
    return _copy(stage: TripTaskStage.cancelled);
  }

  TripTask _copy({
    required TripTaskStage stage,
    DateTime? startedAt,
    DateTime? fieldEnteredAt,
    DateTime? completedAt,
  }) => TripTask(
    id: id,
    destinationName: destinationName,
    destination: destination,
    travelMode: travelMode,
    stage: stage,
    createdAt: createdAt,
    startedAt: startedAt ?? this.startedAt,
    fieldEnteredAt: fieldEnteredAt ?? this.fieldEnteredAt,
    completedAt: completedAt ?? this.completedAt,
    sessionId: sessionId,
    targetId: targetId,
  );

  void _requireOpen(String operation) {
    if (!isOpen) {
      throw StateError('cannot $operation a ${stage.name} trip task');
    }
  }
}

/// Transient controller for the current task. Persistence is intentionally
/// deferred until the 2.0 task flow is validated end to end.
class TripTaskController extends Notifier<TripTask?> {
  int _nextId = 0;

  @override
  TripTask? build() => null;

  TripTask plan({
    required String destinationName,
    required GeoPoint destination,
    required TripTravelMode travelMode,
    String? sessionId,
    String? targetId,
  }) {
    final current = state;
    if (current != null &&
        current.isOpen &&
        _sameDestination(current.destination, destination) &&
        current.travelMode == travelMode &&
        current.sessionId == sessionId &&
        current.targetId == targetId) {
      return current;
    }
    final task = TripTask(
      id: 'trip_${DateTime.now().microsecondsSinceEpoch}_${_nextId++}',
      destinationName: destinationName,
      destination: destination,
      travelMode: travelMode,
      stage: TripTaskStage.planning,
      createdAt: DateTime.now().toUtc(),
      sessionId: sessionId,
      targetId: targetId,
    );
    state = task;
    return task;
  }

  void start({DateTime? at}) {
    final current = state;
    if (current == null) return;
    state = current.start(at: at);
  }

  void enterField({DateTime? at}) {
    final current = state;
    if (current == null) return;
    state = current.enterField(at: at);
  }

  void complete({DateTime? at}) {
    final current = state;
    if (current == null) return;
    state = current.complete(at: at);
  }

  void cancel() {
    final current = state;
    if (current == null) return;
    state = current.cancel();
  }

  void clear() => state = null;

  static bool _sameDestination(GeoPoint first, GeoPoint second) =>
      first.latitude == second.latitude &&
      first.longitude == second.longitude &&
      first.coordinateSystem == second.coordinateSystem;
}

final tripTaskProvider = NotifierProvider<TripTaskController, TripTask?>(
  TripTaskController.new,
);
