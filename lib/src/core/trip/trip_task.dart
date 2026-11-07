import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/mission/mission_providers.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';
import 'package:luma_nest/src/core/persistence/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single user-facing task that connects planning, departure and field
/// work in 2.0. Route geometry, weather and shooting evidence remain owned by
/// their existing providers; this object only owns the user's intent and its
/// lifecycle.
enum TripTaskStage { planning, enRoute, field, completed, cancelled }

enum TripTravelMode { driving, walking }

String tripTaskPlanErrorMessage(StateError error) => switch (error.message) {
  'trip_restore_pending' => '正在恢复之前的出行，请稍后重试。',
  'trip_restore_failed' => '无法读取之前的出行，请检查本地存储并重启应用。',
  _ => '当前出行已有云端任务，请先确认云端任务已结束，再更换目的地。',
};

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
    final raw = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    // A question mentioning an action is not an instruction to execute it.
    // Fuzzy text remains ordinary Q&A, never a direct task mutation.
    if (raw.isEmpty ||
        raw.length > 80 ||
        raw.contains('?') ||
        raw.contains('？')) {
      return null;
    }
    final text = raw.replaceFirst(RegExp(r'[。！!]+$'), '');
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
    if (RegExp(r'^(?:我到了(?:，进入现场)?|我已到达|已到达|进入现场|开启现场模式)$')
        .hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.enterField);
    }
    if (RegExp(r'^(?:结束这次(?:行程)?|完成这次(?:行程)?|结束任务|完成任务)$')
        .hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.complete);
    }
    if (RegExp(r'^(?:停止守候|关闭守候|暂停守候)$').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.stopWatch);
    }
    if (RegExp(r'^(?:开启守候|开始守候)$').hasMatch(text)) {
      return const TripTaskCommand(TripTaskCommandType.startWatch);
    }
    if (RegExp(r'^(?:取消任务|停止这次|取消这次行程)$').hasMatch(text)) {
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
    this.remoteCreationPending = false,
    this.pendingWatchEnabled,
    this.pendingWatchVersion,
    this.pendingWatchIntentRevision,
    this.pendingTransition,
    this.pendingTransitionVersion,
    this.watchEnabled = false,
    this.watchIntentRevision = 0,
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

  /// A create may have reached the server even if its response was lost.
  final bool remoteCreationPending;
  final bool? pendingWatchEnabled;
  final int? pendingWatchVersion;

  /// The immutable intent revision captured when the pending watch request
  /// was queued. A later local toggle must not change the request body that
  /// will be replayed after a lost response or restart.
  final int? pendingWatchIntentRevision;
  final String? pendingTransition;
  final int? pendingTransitionVersion;
  final bool watchEnabled;
  final int watchIntentRevision;

  bool get isOpen =>
      stage != TripTaskStage.completed && stage != TripTaskStage.cancelled;

  bool get isEnRoute => stage == TripTaskStage.enRoute;

  bool get isInField => stage == TripTaskStage.field;

  Map<String, Object?> toJson() => {
    'version': 4,
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
    'watchIntentRevision': watchIntentRevision,
    'remoteCreationPending': remoteCreationPending,
    if (pendingWatchEnabled != null) 'pendingWatchEnabled': pendingWatchEnabled,
    if (pendingWatchVersion != null) 'pendingWatchVersion': pendingWatchVersion,
    if (pendingWatchIntentRevision != null)
      'pendingWatchIntentRevision': pendingWatchIntentRevision,
    if (pendingTransition != null) 'pendingTransition': pendingTransition,
    if (pendingTransitionVersion != null)
      'pendingTransitionVersion': pendingTransitionVersion,
  };

  static TripTask? fromJson(Object? raw) {
    if (raw is! Map || ![1, 2, 3, 4].contains(raw['version'])) {
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
    // Older snapshots cannot establish that background monitoring was
    // explicitly authorized. Preserve the trip, but request suspension.
    final legacy = raw['version'] != 4;
    final remoteMissionWatchEnabled = raw['remoteMissionWatchEnabled'] is bool
        ? raw['remoteMissionWatchEnabled'] as bool
        : null;
    final watchEnabled = !legacy && raw['watchEnabled'] == true;
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
      remoteCreationPending: raw['remoteCreationPending'] == true,
      pendingWatchEnabled:
          (!legacy || raw['pendingWatchEnabled'] == false) &&
              raw['pendingWatchEnabled'] is bool
          ? raw['pendingWatchEnabled'] as bool
          : null,
      pendingWatchVersion:
          (!legacy || raw['pendingWatchEnabled'] == false) &&
              raw['pendingWatchVersion'] is int
          ? raw['pendingWatchVersion'] as int
          : null,
      pendingWatchIntentRevision:
          (!legacy || raw['pendingWatchEnabled'] == false) &&
              raw['pendingWatchIntentRevision'] is int &&
              (raw['pendingWatchIntentRevision'] as int) >= 0
          ? raw['pendingWatchIntentRevision'] as int
          : null,
      pendingTransition: raw['pendingTransition'] is String
          ? raw['pendingTransition'] as String
          : null,
      pendingTransitionVersion: raw['pendingTransitionVersion'] is int
          ? raw['pendingTransitionVersion'] as int
          : null,
      watchEnabled: watchEnabled,
      watchIntentRevision:
          raw['watchIntentRevision'] is int &&
              (raw['watchIntentRevision'] as int) >= 0
          ? raw['watchIntentRevision'] as int
          : 0,
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
    bool? remoteCreationPending,
    bool? pendingWatchEnabled,
    int? pendingWatchVersion,
    int? pendingWatchIntentRevision,
    bool clearPendingWatch = false,
    String? pendingTransition,
    int? pendingTransitionVersion,
    bool clearPendingTransition = false,
    bool? watchEnabled,
    int? watchIntentRevision,
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
    remoteCreationPending: remoteCreationPending ?? this.remoteCreationPending,
    pendingWatchEnabled: clearPendingWatch
        ? null
        : pendingWatchEnabled ?? this.pendingWatchEnabled,
    pendingWatchVersion: clearPendingWatch
        ? null
        : pendingWatchVersion ?? this.pendingWatchVersion,
    pendingWatchIntentRevision: clearPendingWatch
        ? null
        : pendingWatchIntentRevision ?? this.pendingWatchIntentRevision,
    pendingTransition: clearPendingTransition
        ? null
        : pendingTransition ?? this.pendingTransition,
    pendingTransitionVersion: clearPendingTransition
        ? null
        : pendingTransitionVersion ?? this.pendingTransitionVersion,
    watchEnabled: watchEnabled ?? this.watchEnabled,
    watchIntentRevision: watchIntentRevision ?? this.watchIntentRevision,
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

/// Stores the task and its pending recovery marker in a single SQLite row.
/// A null snapshot is a tombstone so an old preferences value cannot reappear.
class DriftTripTaskStore implements TripTaskStore {
  DriftTripTaskStore(this._database, this._preferences);

  final AppDatabase _database;
  final SharedPreferencesAsync _preferences;

  @override
  Future<TripTask?> read() async {
    var row = await _database
        .customSelect('SELECT snapshot FROM trip_task_state WHERE id = 1')
        .getSingleOrNull();
    if (row == null) {
      final legacy = await _preferences.getString(
        SharedPreferencesTripTaskStore._key,
      );
      // Validate before copying; a corrupt value must never be silently lost.
      if (legacy != null) _decode(legacy);
      await _database.customStatement(
        'INSERT OR IGNORE INTO trip_task_state (id, snapshot) VALUES (1, ?)',
        [legacy],
      );
      row = await _database
          .customSelect('SELECT snapshot FROM trip_task_state WHERE id = 1')
          .getSingle();
    }
    final snapshot = row.readNullable<String>('snapshot');
    final task = snapshot == null ? null : _decode(snapshot);
    // SQLite is authoritative only after its row has committed and decoded.
    // Cleanup is best effort; the row (including a tombstone) always wins.
    try {
      await _preferences.remove(SharedPreferencesTripTaskStore._key);
    } on Object catch (error) {
      debugPrint('TripTask legacy cleanup failed: $error');
    }
    return task;
  }

  TripTask _decode(String snapshot) {
    final task = TripTask.fromJson(jsonDecode(snapshot));
    if (task == null) throw const FormatException('Invalid trip task snapshot');
    return task;
  }

  @override
  Future<void> write(TripTask task) => _setSnapshot(jsonEncode(task.toJson()));

  @override
  Future<void> clear() => _setSnapshot(null);

  Future<void> _setSnapshot(String? snapshot) => _database.customStatement(
    'INSERT INTO trip_task_state (id, snapshot) VALUES (1, ?) '
    'ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot',
    [snapshot],
  );
}

final tripTaskStoreProvider = Provider<TripTaskStore>(
  (ref) => DriftTripTaskStore(
    ref.watch(appDatabaseProvider),
    SharedPreferencesAsync(),
  ),
);

class TripTaskController extends Notifier<TripTask?> {
  int _nextId = 0;
  int _mutationRevision = 0;
  bool _restored = false;
  bool _restoreFailed = false;
  late Future<void> _restoreFuture;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _missionSyncQueue = Future<void>.value();
  int _versionConflictRetries = 0;

  Future<void> get ready => _restoreFuture;

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
    } on Object catch (error) {
      // A failed read leaves the previous cloud state unknown. Do not let a
      // new task overwrite that snapshot until recovery succeeds.
      _restoreFailed = true;
      debugPrint('TripTask restore failed: $error');
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
      if (restored.remoteCreationPending ||
          (restored.remoteMissionId != null &&
              restored.remoteMissionStage != MissionRemoteStage.completed &&
              restored.remoteMissionStage != MissionRemoteStage.cancelled)) {
        state = restored;
        _persist(restored);
        _scheduleMissionSync(restored);
        return;
      }
      unawaited(store.clear());
      return;
    }
    state = restored;
    _persist(restored);
    _projectRouteContext(restored);
    if (restored.remoteMissionId != null || restored.remoteCreationPending) {
      _scheduleMissionSync(restored);
    }
  }

  TripTask plan({
    required String destinationName,
    required GeoPoint destination,
    required TripTravelMode travelMode,
    String? sessionId,
    String? targetId,
  }) {
    if (!_restored) throw StateError('trip_restore_pending');
    if (_restoreFailed) throw StateError('trip_restore_failed');
    final current = state;
    if (current != null &&
        current.isOpen &&
        _sameDestination(current.destination, destination) &&
        current.travelMode == travelMode &&
        current.sessionId == sessionId &&
        current.targetId == targetId) {
      return current;
    }
    if (current != null &&
        (current.remoteCreationPending ||
            (current.remoteMissionId != null &&
                current.remoteMissionStage != MissionRemoteStage.completed &&
                current.remoteMissionStage != MissionRemoteStage.cancelled) ||
            (current.isOpen && current.watchEnabled))) {
      throw StateError('cloud_trip_requires_reconciliation');
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
    if (current == null) return;
    final remoteAlreadyMatches = current.remoteMissionWatchEnabled == enabled;
    if (current.watchEnabled == enabled && remoteAlreadyMatches) return;
    final next = current._copy(
      stage: current.stage,
      watchEnabled: enabled,
      watchIntentRevision: current.watchIntentRevision + 1,
      remoteCreationPending:
          current.remoteCreationPending ||
          (enabled && current.remoteMissionId == null),
    );
    state = next;
    _mutationRevision += 1;
    _persist(next);
    _scheduleMissionSync(next);
  }

  void clear() {
    if (!_restored) throw StateError('trip_restore_pending');
    if (_restoreFailed) throw StateError('trip_restore_failed');
    final current = state;
    if (current?.remoteCreationPending == true ||
        (current?.remoteMissionId != null &&
            current?.remoteMissionStage != MissionRemoteStage.completed &&
            current?.remoteMissionStage != MissionRemoteStage.cancelled)) {
      throw StateError('cloud_trip_requires_reconciliation');
    }
    state = null;
    _mutationRevision += 1;
    _enqueuePersistence((store) => store.clear());
    ref.read(routeContextStateProvider.notifier).end();
  }

  void _persist(TripTask task) {
    _enqueuePersistence((store) => store.write(task));
  }

  void _scheduleMissionSync(TripTask task) {
    if (task.remoteMissionId == null && !task.remoteCreationPending) return;
    final repository = ref.read(missionRemoteRepositoryProvider);
    if (repository == null) return;
    final queued = _missionSyncQueue
        .catchError((Object error, StackTrace stack) {})
        .then((_) async {
          // Do not send a create if writing its recovery marker fails.
          await _writeQueue;
          final current = state;
          if (current == null || current.id != task.id) return;
          await _syncMission(repository, current);
        });
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
    // Unknown remote state is not evidence that the desired state is active.
    // Force an explicit setWatch reconciliation instead of guessing.
    var remoteWatchEnabled =
        task.remoteMissionWatchEnabled ?? !task.watchEnabled;
    if (remoteId == null || remoteVersion == null) {
      final createOperation = _missionOperationId(task, 'create');
      MissionRemoteSnapshot? created;
      try {
        created = await repository.create(
          MissionDraft(
            destinationName: task.destinationName,
            latitude: task.destination.latitude,
            longitude: task.destination.longitude,
            intent: 'photography',
            locale: 'zh-CN',
            // Create dormant: an opt-out while this request is in flight must
            // never turn on background checks as a side effect of recovery.
            watchEnabled: false,
          ),
          operationId: createOperation,
        );
      } on MissionLegacyOperationUnverifiable {
        final record = await repository.getOperation(createOperation);
        if (record == null ||
            record.verifiable ||
            record.status != 201 ||
            record.missionId == null) {
          return;
        }
        final recovered = await repository.get(record.missionId!);
        if (recovered == null ||
            recovered.id != record.missionId ||
            recovered.destinationName != task.destinationName ||
            recovered.destinationLatitude != task.destination.latitude ||
            recovered.destinationLongitude != task.destination.longitude ||
            recovered.destinationSystem != 'wgs84' ||
            recovered.intent != 'photography') {
          return;
        }
        created = recovered;
      }
      if (created == null || state?.id != task.id) return;
      final latest = await repository.get(created.id);
      if (latest == null ||
          latest.id != created.id ||
          latest.version < created.version ||
          state?.id != task.id) {
        return;
      }
      remoteId = latest.id;
      remoteVersion = latest.version;
      remoteStage = latest.stage;
      remoteWatchEnabled = latest.watchEnabled;
      _attachMission(task.id, latest);
      // The user may have changed their mind while create was in flight.
      task = state!;
    } else {
      // The local stage remains authoritative for the immediate UI; the
      // persisted remote stage is used to make a missed sync retryable.
    }
    final missionId = remoteId;
    var expectedVersion = remoteVersion;
    if (task.pendingTransition != null &&
        task.pendingTransitionVersion != null) {
      final replayed = await _sendPendingTransition(
        repository,
        task,
        missionId,
      );
      if (replayed == null || state?.id != task.id) return;
      expectedVersion = replayed.version;
      remoteStage = replayed.stage;
      remoteWatchEnabled = replayed.watchEnabled;
      task = state!;
    }
    if (task.pendingWatchVersion != null && task.pendingWatchEnabled != null) {
      final replayed = await _sendPendingWatch(repository, task, missionId);
      if (replayed == null || state?.id != task.id) return;
      expectedVersion = replayed.version;
      remoteStage = replayed.stage;
      remoteWatchEnabled = replayed.watchEnabled;
      task = state!;
    }
    // Replayed operations acknowledge historical results. Only the current
    // server record may be used as the basis for another transition.
    final latest = await repository.get(missionId);
    if (latest == null ||
        latest.id != missionId ||
        latest.version < expectedVersion ||
        state?.id != task.id) {
      return;
    }
    expectedVersion = latest.version;
    remoteStage = latest.stage;
    remoteWatchEnabled = latest.watchEnabled;
    _attachMission(task.id, latest);
    task = state!;
    final desired = _remoteStageFor(task.stage);
    if (desired != remoteStage) {
      final operations = _missionOperations(remoteStage, desired);
      for (final operation in operations) {
        final current = state;
        if (current == null ||
            current.id != task.id ||
            current.stage != task.stage) {
          return;
        }
        final pending = current._copy(
          stage: current.stage,
          pendingTransition: operation,
          pendingTransitionVersion: expectedVersion,
        );
        state = pending;
        _persist(pending);
        await _writeQueue;
        final updated = await _sendPendingTransition(
          repository,
          pending,
          missionId,
        );
        if (updated == null || state?.id != task.id) return;
        expectedVersion = updated.version;
        remoteStage = updated.stage;
        remoteWatchEnabled = updated.watchEnabled;
      }
    }
    final current = state;
    if (current == null || current.id != task.id || !current.isOpen) return;
    if (remoteWatchEnabled != current.watchEnabled) {
      final pending = current._copy(
        stage: current.stage,
        pendingWatchEnabled: current.watchEnabled,
        pendingWatchVersion: expectedVersion,
        pendingWatchIntentRevision: current.watchIntentRevision,
      );
      state = pending;
      _persist(pending);
      // The operation and its exact payload must be stored before sending.
      await _writeQueue;
      await _sendPendingWatch(repository, pending, missionId);
    }
  }

  Future<MissionRemoteSnapshot?> _sendPendingTransition(
    MissionRemoteRepository repository,
    TripTask task,
    String missionId,
  ) async {
    final operation = task.pendingTransition!;
    final version = task.pendingTransitionVersion!;
    MissionRemoteSnapshot? updated;
    try {
      updated = await repository.patch(
        missionId,
        expectedVersion: version,
        operation: operation,
        operationId: _missionOperationId(task, operation, version),
      );
    } on MissionVersionConflict catch (conflict) {
      await _reconcileVersionConflict(
        repository,
        task,
        missionId,
        version,
        conflict.current,
        clearTransition: true,
      );
      return null;
    } on MissionLegacyOperationUnverifiable {
      return _recoverLegacyOperation(
        repository,
        task,
        missionId,
        _missionOperationId(task, operation, version),
        clearTransition: true,
      );
    }
    if (updated == null || state?.id != task.id) return null;
    final latest = await repository.get(missionId);
    if (latest == null ||
        latest.id != missionId ||
        latest.version < updated.version ||
        state?.id != task.id) {
      return null;
    }
    _attachMission(task.id, latest, clearPendingTransition: true);
    _versionConflictRetries = 0;
    return latest;
  }

  Future<MissionRemoteSnapshot?> _sendPendingWatch(
    MissionRemoteRepository repository,
    TripTask task,
    String missionId,
  ) async {
    final enabled = task.pendingWatchEnabled!;
    final version = task.pendingWatchVersion!;
    final intentRevision =
        task.pendingWatchIntentRevision ?? task.watchIntentRevision;
    MissionRemoteSnapshot? updated;
    try {
      updated = await repository.patch(
        missionId,
        expectedVersion: version,
        operation: enabled ? 'authorizeWatch' : 'setWatch',
        operationId: _missionOperationId(
          task,
          enabled ? 'setWatch-on' : 'setWatch-off',
          version,
        ),
        watchEnabled: enabled,
        intentRevision: intentRevision,
      );
    } on MissionVersionConflict catch (conflict) {
      await _reconcileVersionConflict(
        repository,
        task,
        missionId,
        version,
        conflict.current,
        clearTransition: false,
      );
      return null;
    } on MissionLegacyOperationUnverifiable {
      return _recoverLegacyOperation(
        repository,
        task,
        missionId,
        _missionOperationId(
          task,
          enabled ? 'setWatch-on' : 'setWatch-off',
          version,
        ),
        clearTransition: false,
      );
    }
    if (updated == null || state?.id != task.id) return null;
    final latest = await repository.get(missionId);
    if (latest == null ||
        latest.id != missionId ||
        latest.version < updated.version ||
        state?.id != task.id) {
      return null;
    }
    _attachMission(task.id, latest, clearPendingWatch: true);
    _versionConflictRetries = 0;
    return latest;
  }

  Future<MissionRemoteSnapshot?> _recoverLegacyOperation(
    MissionRemoteRepository repository,
    TripTask task,
    String missionId,
    String operationId, {
    required bool clearTransition,
  }) async {
    final record = await repository.getOperation(operationId);
    if (record == null ||
        record.verifiable ||
        record.status != 200 ||
        record.missionId != missionId) {
      return null;
    }
    final latest = await repository.get(missionId);
    if (latest == null || latest.id != missionId || state?.id != task.id) {
      return null;
    }
    final current = state!;
    if (current.remoteMissionId == missionId &&
        current.remoteMissionVersion != null &&
        latest.version < current.remoteMissionVersion!) {
      return null;
    }
    _attachMission(
      task.id,
      latest,
      clearPendingTransition: clearTransition,
      clearPendingWatch: !clearTransition,
    );
    final currentAfterReconcile = state;
    if (currentAfterReconcile != null &&
        !clearTransition &&
        currentAfterReconcile.watchEnabled != latest.watchEnabled) {
      final rebased = currentAfterReconcile._copy(
        stage: currentAfterReconcile.stage,
        watchIntentRevision: latest.watchIntentRevision + 1,
      );
      state = rebased;
      _persist(rebased);
    }
    return latest;
  }

  Future<void> _reconcileVersionConflict(
    MissionRemoteRepository repository,
    TripTask task,
    String missionId,
    int rejectedVersion,
    MissionRemoteSnapshot conflict, {
    required bool clearTransition,
  }) async {
    if (conflict.id != missionId || conflict.version <= rejectedVersion) return;
    final latest = await repository.get(missionId);
    if (latest == null ||
        latest.id != missionId ||
        latest.version < conflict.version ||
        state?.id != task.id) {
      return;
    }
    _attachMission(
      task.id,
      latest,
      clearPendingTransition: clearTransition,
      clearPendingWatch: !clearTransition,
    );
    // A bounded immediate retry handles ordinary races without spinning if a
    // second device continuously changes the same Mission.
    if (++_versionConflictRetries <= 3 && state != null) {
      _scheduleMissionSync(state!);
    }
  }

  void _attachMission(
    String taskId,
    MissionRemoteSnapshot snapshot, {
    bool clearPendingWatch = false,
    bool clearPendingTransition = false,
  }) {
    final current = state;
    if (current == null || current.id != taskId) return;
    if (current.remoteMissionId == snapshot.id &&
        current.remoteMissionVersion != null &&
        snapshot.version < current.remoteMissionVersion!) {
      return;
    }
    final next = current._copy(
      stage: current.stage,
      remoteMissionId: snapshot.id,
      remoteMissionVersion: snapshot.version,
      remoteMissionStage: snapshot.stage,
      remoteMissionWatchEnabled: snapshot.watchEnabled,
      watchIntentRevision:
          snapshot.watchIntentRevision > current.watchIntentRevision
          ? snapshot.watchIntentRevision
          : current.watchIntentRevision,
      remoteCreationPending: false,
      clearPendingWatch: clearPendingWatch,
      clearPendingTransition: clearPendingTransition,
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
