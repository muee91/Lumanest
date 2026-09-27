import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 17, 10);

  test('notification payload targets only its stable session ID', () {
    expect(
      shootingSessionNotificationPayloadFor('session-blue-hour'),
      '/session/session-blue-hour',
    );
    expect(
      shootingSessionNotificationPayloadFor(
        'session-blue-hour',
        targetId: 'target-north-ridge',
      ),
      '/session/session-blue-hour?target=target-north-ridge',
    );
  });

  test(
    'schedules an explicit watch fifteen minutes before session start',
    () async {
      final service = _FakeService();
      final ledger = _MemoryLedger();
      final session = _sessionStarting(now.add(const Duration(minutes: 35)));
      final reconciler = _reconciler(service, ledger, now);

      await reconciler.reconcile(
        snapshot: _snapshot(now, session),
        library: _library(now, session),
      );

      expect(service.scheduled, hasLength(1));
      expect(
        service.scheduled.single.notifyAt,
        now.add(const Duration(minutes: 20)),
      );
      expect(service.scheduled.single.session.id, session.id);
    },
  );

  test('uses the route departure deadline when one is available', () async {
    final service = _FakeService();
    final session = _sessionStarting(now.add(const Duration(minutes: 35)));
    final deadline = now.add(const Duration(minutes: 7));
    final plan = ShootingDeparturePlan(
      sessionId: session.id,
      departureDeadline: deadline,
      routeDuration: const Duration(minutes: 22),
      createdAt: now,
    );

    await _reconciler(service, _MemoryLedger(), now).reconcile(
      snapshot: _snapshot(now, session),
      library: _library(now, session),
      departurePlan: plan,
    );

    expect(service.scheduled.single.notifyAt, deadline);
    expect(service.scheduled.single.departureDeadline, deadline);
  });

  test('does not apply a route deadline to another reviewed target', () async {
    final service = _FakeService();
    final ledger = _MemoryLedger();
    final session = _sessionStarting(now.add(const Duration(minutes: 35)));
    final plan = ShootingDeparturePlan(
      sessionId: session.id,
      targetId: 'target-a',
      departureDeadline: now.add(const Duration(minutes: 7)),
      routeDuration: const Duration(minutes: 22),
      createdAt: now,
    );

    await _reconciler(service, ledger, now).reconcile(
      snapshot: _snapshot(now, session),
      library: _library(now, session, targetId: 'target-b'),
      departurePlan: plan,
    );

    expect(
      service.scheduled.single.notifyAt,
      session.startsAt.subtract(const Duration(minutes: 15)),
    );
    expect(service.scheduled.single.departureDeadline, isNull);
  });

  test(
    'does not apply a target-specific departure plan to a legacy targetless watch',
    () async {
      final service = _FakeService();
      final session = _sessionStarting(now.add(const Duration(minutes: 35)));
      final plan = ShootingDeparturePlan(
        sessionId: session.id,
        targetId: 'target-a',
        departureDeadline: now.add(const Duration(minutes: 7)),
        routeDuration: const Duration(minutes: 22),
        createdAt: now,
      );

      await _reconciler(service, _MemoryLedger(), now).reconcile(
        snapshot: _snapshot(now, session),
        library: _library(now, session),
        departurePlan: plan,
      );

      expect(
        service.scheduled.single.notifyAt,
        session.startsAt.subtract(const Duration(minutes: 15)),
      );
      expect(service.scheduled.single.departureDeadline, isNull);
    },
  );

  test(
    'keeps an earlier scheduled departure reminder after transient route state is lost',
    () async {
      final service = _FakeService();
      final ledger = _MemoryLedger();
      final session = _sessionStarting(now.add(const Duration(minutes: 35)));
      final library = _library(now, session, targetId: 'target-a');
      final deadline = now.add(const Duration(minutes: 7));
      final plan = ShootingDeparturePlan(
        sessionId: session.id,
        targetId: 'target-a',
        departureDeadline: deadline,
        routeDuration: const Duration(minutes: 22),
        createdAt: now,
      );
      final reconciler = _reconciler(service, ledger, now);

      await reconciler.reconcile(
        snapshot: _snapshot(now, session),
        library: library,
        departurePlan: plan,
      );
      await reconciler.reconcile(
        snapshot: _snapshot(now, session),
        library: library,
      );

      expect(service.scheduled, hasLength(1));
      expect(service.cancelled, isEmpty);
      final record = (await ledger.read()).values.single;
      expect(record.watchId, library.watchedSessions.single.id);
      expect(record.notifyAt, deadline);
      expect(record.notificationType, ShootingNotificationType.departure);
    },
  );

  test(
    'explicit departure invalidation downgrades an obsolete earlier reminder',
    () async {
      final service = _FakeService();
      final ledger = _MemoryLedger();
      final session = _sessionStarting(now.add(const Duration(minutes: 35)));
      final library = _library(now, session, targetId: 'target-a');
      final deadline = now.add(const Duration(minutes: 7));
      final plan = ShootingDeparturePlan(
        sessionId: session.id,
        targetId: 'target-a',
        departureDeadline: deadline,
        routeDuration: const Duration(minutes: 22),
        createdAt: now,
      );
      final reconciler = _reconciler(service, ledger, now);

      await reconciler.reconcile(
        snapshot: _snapshot(now, session),
        library: library,
        departurePlan: plan,
      );
      await reconciler.reconcile(
        snapshot: _snapshot(now, session),
        library: library,
        departureInvalidation: ShootingDeparturePlanInvalidation(
          sessionId: session.id,
          targetId: 'target-a',
        ),
      );

      expect(service.scheduled, hasLength(2));
      expect(service.cancelled, [library.watchedSessions.single.id]);
      expect(
        service.scheduled.last.notifyAt,
        session.startsAt.subtract(const Duration(minutes: 15)),
      );
      expect(service.scheduled.last.departureDeadline, isNull);
    },
  );

  test('uses one immediate notification for a current session', () async {
    final service = _FakeService();
    final session = _sessionStarting(now.subtract(const Duration(minutes: 2)));

    await _reconciler(service, _MemoryLedger(), now).reconcile(
      snapshot: _snapshot(now, session),
      library: _library(now, session),
    );

    expect(service.scheduled.single.notifyAt, now);
  });

  test('提醒携带快照的数据时间，不暗示自己读到的是实时', () async {
    final service = _FakeService();
    final session = _sessionStarting(now.add(const Duration(minutes: 35)));

    await _reconciler(service, _MemoryLedger(), now).reconcile(
      snapshot: _snapshot(now, session),
      library: _library(now, session),
    );

    expect(service.scheduled.single.dataObservedAt, now);
  });

  test('提醒正文只陈述窗口、成立条件与数据时间', () {
    final session = ContextFixtures.waterEveningSession(
      observedAt: DateTime.utc(2026, 7, 18, 10, 40),
    );

    final body = LocalShootingSessionNotificationService.reasonFor(
      session,
      DateTime.utc(2026, 7, 18, 10, 40),
    );

    expect(
      body,
      '窗口 ${_clock(session.startsAt)} 开始 · '
      '成立条件：云量 58% · 风速 2.1m/s · '
      '依据 ${_clock(DateTime.utc(2026, 7, 18, 10, 40))} 的数据',
    );
    for (final claim in <String>['概率', '成功率', '把握']) {
      expect(body, isNot(contains(claim)), reason: '未校准的分数不得伪装成 $claim');
    }
  });

  test('stale or missing sessions cancel their prior notification', () async {
    final service = _FakeService();
    final ledger = _MemoryLedger();
    final session = _sessionStarting(now.add(const Duration(minutes: 35)));
    final library = _library(now, session);
    final reconciler = _reconciler(service, ledger, now);

    await reconciler.reconcile(
      snapshot: _snapshot(now, session),
      library: library,
    );
    await reconciler.reconcile(
      snapshot: _snapshot(now, null, stale: true),
      library: library,
    );

    expect(service.cancelled, [library.watchedSessions.single.id]);
    expect(await ledger.read(), isEmpty);
  });

  test('target changes replace the old watch notification identity', () async {
    final service = _FakeService();
    final ledger = _MemoryLedger();
    final session = _sessionStarting(now.add(const Duration(minutes: 35)));
    final first = _library(now, session, targetId: 'target-a');
    final second = _library(now, session, targetId: 'target-b');
    final reconciler = _reconciler(service, ledger, now);

    await reconciler.reconcile(
      snapshot: _snapshot(now, session),
      library: first,
    );
    await reconciler.reconcile(
      snapshot: _snapshot(now, session),
      library: second,
    );

    expect(service.scheduled, hasLength(2));
    expect(service.cancelled, [first.watchedSessions.single.id]);
    expect((await ledger.read()).keys, [second.watchedSessions.single.id]);
    expect(service.scheduled.last.watchTargetId, 'target-b');
  });

  test('permission-denied preference cannot be enabled', () async {
    final service = _FakeService(permission: false);
    final preference = _MemoryPreference();
    final container = ProviderContainer(
      overrides: [
        shootingSessionNotificationServiceProvider.overrideWithValue(service),
        shootingSessionNotificationPreferenceStoreProvider.overrideWithValue(
          preference,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(shootingSessionNotificationsEnabledProvider.future);

    final enabled = await container
        .read(shootingSessionNotificationsEnabledProvider.notifier)
        .setEnabled(true);

    expect(enabled, isFalse);
    expect(preference.enabled, isFalse);
    expect(service.permissionRequests, 1);
  });
}

String _clock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

ShootingSession _sessionStarting(DateTime startsAt) =>
    ContextFixtures.waterEveningSession(
      observedAt: startsAt.subtract(const Duration(minutes: 10)),
    );

ContextSnapshot _snapshot(
  DateTime now,
  ShootingSession? session, {
  bool stale = false,
}) => ContextSnapshot(
  id: 'fresh-snapshot',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  primaryScene: SceneType.lake,
  dayPhase: DayPhase.sunset,
  weather: WeatherType.cloudy,
  activeRoute: false,
  isStale: stale,
  shootingSessions: session == null ? const [] : [session],
);

UserLibraryState _library(
  DateTime now,
  ShootingSession session, {
  String? targetId,
}) => UserLibraryState(
  watchedSessions: [
    WatchedShootingSession.create(
      session: session,
      snapshotId: 'fresh-snapshot',
      watchedAt: now.subtract(const Duration(minutes: 1)),
      targetId: targetId,
    ),
  ],
);

ShootingSessionNotificationReconciler _reconciler(
  _FakeService service,
  _MemoryLedger ledger,
  DateTime now,
) => ShootingSessionNotificationReconciler(
  service: service,
  preferences: _MemoryPreference(enabled: true),
  ledger: ledger,
  now: () => now,
);

class _Scheduled {
  const _Scheduled({
    required this.session,
    required this.notifyAt,
    required this.dataObservedAt,
    required this.watchTargetId,
    this.departureDeadline,
  });
  final ShootingSession session;
  final DateTime notifyAt;
  final DateTime dataObservedAt;
  final String? watchTargetId;
  final DateTime? departureDeadline;
}

class _FakeService implements ShootingSessionNotificationService {
  _FakeService({this.permission = true});

  final bool permission;
  var permissionRequests = 0;
  final scheduled = <_Scheduled>[];
  final cancelled = <String>[];

  @override
  Future<void> cancel(String watchId) async => cancelled.add(watchId);

  @override
  Future<bool> permissionGranted() async => permission;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<void> schedule({
    required WatchedShootingSession watch,
    required ShootingSession session,
    required DateTime notifyAt,
    required DateTime dataObservedAt,
    DateTime? departureDeadline,
  }) async {
    scheduled.add(
      _Scheduled(
        session: session,
        notifyAt: notifyAt,
        dataObservedAt: dataObservedAt,
        watchTargetId: watch.targetId,
        departureDeadline: departureDeadline,
      ),
    );
  }
}

class _MemoryLedger implements ShootingSessionNotificationLedger {
  Map<String, WatchScheduleRecord> value = {};

  @override
  Future<Map<String, WatchScheduleRecord>> read() async =>
      Map.unmodifiable(value);

  @override
  Future<void> write(Map<String, WatchScheduleRecord> scheduled) async {
    value = Map.of(scheduled);
  }
}

class _MemoryPreference implements ShootingSessionNotificationPreferenceStore {
  _MemoryPreference({this.enabled = false});
  bool enabled;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;
}
