import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/mission/mission_providers.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single user-facing task that connects planning, departure and field
/// work in 2.0. Route geometry, weather and shooting evidence remain owned by
/// their existing providers; this object only owns the user's intent and its
/// lifecycle.
enum TripTaskStage { planning, enRoute, field, completed, cancelled }

enum TripTravelMode { driving, walking }

enum TripTaskCommandType {
  plan,
  start,
  enterField,
  complete,
  cancel,
  stopWatch,
  startWatch,
}

@immutable
class TripTaskCommand {
  const TripTaskCommand(this.type, {this.destinationQuery});

  final TripTaskCommandType type;
  final String? destinationQuery;
}

abstract final class TripTaskCommandParser {
  static TripTaskCommand? parse(String value) {
    final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty || text.length > 80) return null;
    final planMatch = RegExp(
      r'^(?:带我去|现在去|前往|去|想去)\s*(.{2,32})$',
    ).firstMatch(text);
    if (planMatch != null && planMatch.group(1)!.trim() != '哪里') {
      return TripTaskCommand(
        TripTaskCommandType.plan,
        destinationQuery: planMatch.group(1)!.trim(),
      );
    }
    if (RegExp(r'^(?:开始出发|现在出发|我出发了|出发)$').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.start);
    }
    if (RegExp(r'(?:我到了|已到达|进入现场|开启现场模式)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.enterField);
    }
    if (RegExp(r'(?:结束这次|完成这次|结束任务|完成任务)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.complete);
    }
    if (RegExp(r'(?:停止守候|关闭守候)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.stopWatch);
    }
    if (RegExp(r'(?:开启守候|开始守候)').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.startWatch);
    }
    if (RegExp(r'(?:取消任务|停止这次)').hasMatch(text)) {
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
    this.remoteMissionId,
    this.remoteMissionVersion,
    this.remoteMissionStage,
    this.remoteMissionWatchEnabled,
    this.watchEnabled = false,
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
  final String? remoteMissionId;
  final int? remoteMissionVersion;
  final MissionRemoteStage? remoteMissionStage;
  final bool? remoteMissionWatchEnabled;
  final bool watchEnabled;

  bool get isOpen =>
      stage != TripTaskStage.completed && stage != TripTaskStage.cancelled;

  bool get isEnRoute => stage == TripTaskStage.enRoute;

  bool get isInField => stage == TripTaskStage.field;

  Map<String, Object?> toJson() => {
    'version': 2,
    'id': id,
    'destinationName': destinationName,
    'destination': {
      'latitude': destination.latitude,
      'longitude': destination.longitude,
      'coordinateSystem': destination.coordinateSystem.name,
    },
    'travelMode': travelMode.name,
    'stage': stage.name,
    'createdAt': createdAt.toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (fieldEnteredAt != null)
      'fieldEnteredAt': fieldEnteredAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (sessionId != null) 'sessionId': sessionId,
    if (targetId != null) 'targetId': targetId,
    if (remoteMissionId != null) 'remoteMissionId': remoteMissionId,
    if (remoteMissionVersion != null)
      'remoteMissionVersion': remoteMissionVersion,
    if (remoteMissionStage != null)
      'remoteMissionStage': remoteMissionStage!.name,
    if (remoteMissionWatchEnabled != null)
      'remoteMissionWatchEnabled': remoteMissionWatchEnabled,
    'watchEnabled': watchEnabled,
  };

  static TripTask? fromJson(Object? raw) {
    if (raw is! Map || (raw['version'] != 1 && raw['version'] != 2)) {
      return null;
    }
    final destination = raw['destination'];
    if (destination is! Map) return null;
    final latitude = _finite(destination['latitude'], -90, 90);
    final longitude = _finite(destination['longitude'], -180, 180);
    final coordinateSystem = _enumByName(
      CoordinateSystem.values,
      destination['coordinateSystem'],
    );
    final travelMode = _enumByName(TripTravelMode.values, raw['travelMode']);
    final stage = _enumByName(TripTaskStage.values, raw['stage']);
    final id = _boundedString(raw['id'], 96);
    final destinationName = _boundedString(raw['destinationName'], 120);
    final createdAt = _date(raw['createdAt']);
    final remoteMissionId = raw['remoteMissionId'] is String
        ? raw['remoteMissionId'] as String
        : null;
    final remoteMissionVersion = raw['remoteMissionVersion'] is int
        ? raw['remoteMissionVersion'] as int
        : null;
    final remoteMissionStage = raw['remoteMissionStage'] is String
        ? _enumByName(MissionRemoteStage.values, raw['remoteMissionStage'])
        : null;
    final remoteMissionWatchEnabled = raw['remoteMissionWatchEnabled'] is bool
        ? raw['remoteMissionWatchEnabled'] as bool
        : null;
    final watchEnabled = raw['watchEnabled'] is bool
        ? raw['watchEnabled'] as bool
        : false;
    if (latitude == null ||
        longitude == null ||
        coordinateSystem == null ||
        travelMode == null ||
        stage == null ||
        id == null ||
        destinationName == null ||
        createdAt == null) {
      return null;
    }
    return TripTask(
      id: id,
      destinationName: destinationName,
      destination: GeoPoint(
        latitude: latitude,
        longitude: longitude,
        coordinateSystem: coordinateSystem,
      ),
      travelMode: travelMode,
      stage: stage,
      createdAt: createdAt,
      startedAt: _date(raw['startedAt']),
      fieldEnteredAt: _date(raw['fieldEnteredAt']),
      completedAt: _date(raw['completedAt']),
      sessionId: _boundedString(raw['sessionId'], 128),
      targetId: _boundedString(raw['targetId'], 128),
      remoteMissionId: remoteMissionId,
      remoteMissionVersion: remoteMissionVersion,
      remoteMissionStage: remoteMissionStage,
      remoteMissionWatchEnabled: remoteMissionWatchEnabled,
      watchEnabled: watchEnabled,
    );
  }

  TripTask start({DateTime? at}) {
    if (stage == TripTaskStage.enRoute) return this;
    if (stage != TripTaskStage.planning) {
      throw StateError('cannot start a ${stage.name} trip task');
    }
    final now = (at ?? DateTime.now()).toUtc();
    return _copy(stage: TripTaskStage.enRoute, startedAt: startedAt ?? now);
  }

  /// Field mode can be entered from planning as well as en-route. This keeps
  /// the task honest when a user arrives without opening an external map.
  TripTask enterField({DateTime? at}) {
    if (stage == TripTaskStage.field) return this;
    if (stage != TripTaskStage.planning && stage != TripTaskStage.enRoute) {
      throw StateError('cannot enterField a ${stage.name} trip task');
    }
    final now = (at ?? DateTime.now()).toUtc();
    return _copy(
      stage: TripTaskStage.field,
      startedAt: startedAt ?? now,
      fieldEnteredAt: fieldEnteredAt ?? now,
    );
  }

  TripTask complete({DateTime? at}) {
    if (stage == TripTaskStage.completed) return this;
    if (stage != TripTaskStage.field) {
      throw StateError('cannot complete a ${stage.name} trip task');
    }
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
    String? remoteMissionId,
    int? remoteMissionVersion,
    MissionRemoteStage? remoteMissionStage,
    bool? remoteMissionWatchEnabled,
    bool? watchEnabled,
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
    remoteMissionId: remoteMissionId ?? this.remoteMissionId,
    remoteMissionVersion: remoteMissionVersion ?? this.remoteMissionVersion,
    remoteMissionStage: remoteMissionStage ?? this.remoteMissionStage,
    remoteMissionWatchEnabled:
        remoteMissionWatchEnabled ?? this.remoteMissionWatchEnabled,
    watchEnabled: watchEnabled ?? this.watchEnabled,
  );

  void _requireOpen(String operation) {
    if (!isOpen) {
      throw StateError('cannot $operation a ${stage.name} trip task');
    }
  }

  static double? _finite(Object? value, double minimum, double maximum) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null &&
            parsed.isFinite &&
            parsed >= minimum &&
            parsed <= maximum
        ? parsed
        : null;
  }

  static String? _boundedString(Object? value, int maximum) {
    if (value is! String || value.isEmpty || value.length > maximum) {
      return null;
    }
    return value;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return parsed?.toUtc();
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}

abstract interface class TripTaskStore {
  Future<TripTask?> read();

  Future<void> write(TripTask task);

  Future<void> clear();
}

class SharedPreferencesTripTaskStore implements TripTaskStore {
  SharedPreferencesTripTaskStore(this._preferences);

  static const _key = 'lumanest.trip_task.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<TripTask?> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null) return null;
    try {
      return TripTask.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(TripTask task) =>
      _preferences.setString(_key, jsonEncode(task.toJson()));

  @override
  Future<void> clear() => _preferences.remove(_key);
}

final tripTaskStoreProvider = Provider<TripTaskStore>(
  (ref) => SharedPreferencesTripTaskStore(SharedPreferencesAsync()),
);

class TripTaskController extends Notifier<TripTask?> {
  int _nextId = 0;
  int _mutationRevision = 0;
  bool _restored = false;
  late Future<void> _restoreFuture;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _missionSyncQueue = Future<void>.value();

  @override
  TripTask? build() {
    final store = ref.watch(tripTaskStoreProvider);
    _restoreFuture = _restore(store, _mutationRevision);
    return null;
  }

  Future<void> _restore(TripTaskStore store, int revisionAtStart) async {
    TripTask? restored;
    try {
      restored = await store.read();
    } on Object {
      // A read failure must not leave the write queue permanently blocked;
      // the next accepted command can still establish a valid snapshot.
      _restored = true;
      return;
    }
    if (_restored || !ref.mounted) return;
    _restored = true;
    // A command may have been accepted while the disk read was in flight.
    // Its state is newer than the snapshot, so never let the late restore
    // overwrite it or clear its freshly queued task.
    if (revisionAtStart != _mutationRevision) return;
    if (restored == null) return;
    if (!restored.isOpen) {
      unawaited(store.clear());
      return;
    }
    state = restored;
    _projectRouteContext(restored);
  }

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
    _mutationRevision += 1;
    _persist(task);
    _projectRouteContext(task);
    _scheduleMissionSync(task);
    return task;
  }

  void start({DateTime? at}) {
    final current = state;
    if (current == null) return;
    final next = current.start(at: at);
    if (identical(next, current)) return;
    state = next;
    _mutationRevision += 1;
    _persist(state!);
    _projectRouteContext(state!);
    _scheduleMissionSync(state!);
  }

  void enterField({DateTime? at}) {
    final current = state;
    if (current == null) return;
    final next = current.enterField(at: at);
    if (identical(next, current)) return;
    state = next;
    _mutationRevision += 1;
    _persist(state!);
    _projectRouteContext(state!);
    _scheduleMissionSync(state!);
  }

  void complete({DateTime? at}) {
    final current = state;
    if (current == null) return;
    final next = current.complete(at: at);
    if (identical(next, current)) return;
    state = next;
    _mutationRevision += 1;
    _persist(state!);
    _projectRouteContext(state!);
    _scheduleMissionSync(state!);
  }

  void cancel() {
    final current = state;
    if (current == null) return;
    final next = current.cancel();
    if (identical(next, current)) return;
    state = next;
    _mutationRevision += 1;
    _persist(state!);
    _projectRouteContext(state!);
    _scheduleMissionSync(state!);
  }

  void setWatchEnabled(bool enabled) {
    final current = state;
    if (current == null || current.watchEnabled == enabled) return;
    final next = current._copy(stage: current.stage, watchEnabled: enabled);
    state = next;
    _mutationRevision += 1;
    _persist(next);
    _scheduleMissionSync(next);
  }

  void clear() {
    state = null;
    _mutationRevision += 1;
    _enqueuePersistence((store) => store.clear());
    ref.read(routeContextStateProvider.notifier).end();
  }

  void _persist(TripTask task) {
    _enqueuePersistence((store) => store.write(task));
  }

  void _scheduleMissionSync(TripTask task) {
    final repository = ref.read(missionRemoteRepositoryProvider);
    if (repository == null) return;
    final queued = _missionSyncQueue
        .catchError((Object error, StackTrace stack) {})
        .then((_) => _syncMission(repository, task));
    _missionSyncQueue = queued;
    unawaited(
      queued.catchError((Object error, StackTrace stack) {
        debugPrint('Mission synchronization failed: $error');
      }),
    );
  }

  Future<void> _syncMission(
    MissionRemoteRepository repository,
    TripTask task,
  ) async {
    if (state?.id != task.id) return;
    var remoteId = task.remoteMissionId;
    var remoteVersion = task.remoteMissionVersion;
    var remoteStage = task.remoteMissionStage ?? MissionRemoteStage.planning;
    var remoteWatchEnabled =
        task.remoteMissionWatchEnabled ?? task.watchEnabled;
    if (remoteId == null || remoteVersion == null) {
      final created = await repository.create(
        MissionDraft(
          destinationName: task.destinationName,
          latitude: task.destination.latitude,
          longitude: task.destination.longitude,
          intent: 'photography',
          locale: 'zh-CN',
          watchEnabled: task.watchEnabled,
        ),
        operationId: _missionOperationId(task, 'create'),
      );
      if (created == null || state?.id != task.id) return;
      remoteId = created.id;
      remoteVersion = created.version;
      remoteStage = created.stage;
      remoteWatchEnabled = created.watchEnabled;
      _attachMission(task.id, created);
    } else {
      // The local stage remains authoritative for the immediate UI; the
      // persisted remote stage is used to make a missed sync retryable.
    }
    final missionId = remoteId;
    var expectedVersion = remoteVersion;
    final desired = _remoteStageFor(task.stage);
    if (desired != remoteStage) {
      final operations = _missionOperations(remoteStage, desired);
      for (final operation in operations) {
        final updated = await repository.patch(
          missionId,
          expectedVersion: expectedVersion,
          operation: operation,
          operationId: _missionOperationId(task, operation, expectedVersion),
        );
        if (updated == null || state?.id != task.id) return;
        expectedVersion = updated.version;
        remoteStage = updated.stage;
        _attachMission(task.id, updated);
      }
    }
    if (remoteWatchEnabled != task.watchEnabled) {
      final updated = await repository.patch(
        missionId,
        expectedVersion: expectedVersion,
        operation: 'setWatch',
        operationId: _missionOperationId(task, 'setWatch', expectedVersion),
        watchEnabled: task.watchEnabled,
      );
      if (updated == null || state?.id != task.id) return;
      _attachMission(task.id, updated);
    }
  }

  void _attachMission(String taskId, MissionRemoteSnapshot snapshot) {
    final current = state;
    if (current == null || current.id != taskId) return;
    final next = current._copy(
      stage: current.stage,
      remoteMissionId: snapshot.id,
      remoteMissionVersion: snapshot.version,
      remoteMissionStage: snapshot.stage,
      remoteMissionWatchEnabled: snapshot.watchEnabled,
      watchEnabled: snapshot.watchEnabled,
    );
    state = next;
    _persist(next);
  }

  static MissionRemoteStage _remoteStageFor(TripTaskStage stage) =>
      MissionRemoteStage.values.firstWhere((value) => value.name == stage.name);

  static List<String> _missionOperations(
    MissionRemoteStage current,
    MissionRemoteStage desired,
  ) {
    if (desired == MissionRemoteStage.cancelled) return const ['cancel'];
    const progression = [
      MissionRemoteStage.planning,
      MissionRemoteStage.enRoute,
      MissionRemoteStage.field,
      MissionRemoteStage.completed,
    ];
    final start = progression.indexOf(current);
    final end = progression.indexOf(desired);
    if (start < 0 || end <= start) return const [];
    const names = ['start', 'arrive', 'complete'];
    return names.sublist(start, end);
  }

  static String _missionOperationId(
    TripTask task,
    String operation, [
    int? version,
  ]) {
    final suffix = version == null ? '' : '-$version';
    return '${task.id}-$operation$suffix';
  }

  void _enqueuePersistence(
    Future<void> Function(TripTaskStore store) operation,
  ) {
    final store = ref.read(tripTaskStoreProvider);
    final queued = _writeQueue
        .catchError((Object error, StackTrace stack) {})
        .then((_) => _restoreFuture)
        .then((_) => operation(store));
    _writeQueue = queued;
    unawaited(
      queued.catchError((Object error, StackTrace stack) {
        debugPrint('TripTask persistence failed: $error');
      }),
    );
  }

  void _projectRouteContext(TripTask task) {
    if (!task.isOpen) {
      ref.read(routeContextStateProvider.notifier).end();
      return;
    }
    final mode = task.travelMode == TripTravelMode.walking
        ? ContextRouteMode.hiking
        : ContextRouteMode.driving;
    final routeController = ref.read(routeContextStateProvider.notifier);
    routeController.plan(
      mode,
      identity: RouteIdentity(
        latitude: task.destination.latitude,
        longitude: task.destination.longitude,
        mode: mode,
      ),
    );
    if (task.stage == TripTaskStage.enRoute ||
        task.stage == TripTaskStage.field) {
      routeController.start();
    }
  }

  static bool _sameDestination(GeoPoint first, GeoPoint second) =>
      first.latitude == second.latitude &&
      first.longitude == second.longitude &&
      first.coordinateSystem == second.coordinateSystem;
}

final tripTaskProvider = NotifierProvider<TripTaskController, TripTask?>(
  TripTaskController.new,
);
