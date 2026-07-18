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

  test('uses one immediate notification for a current session', () async {
    final service = _FakeService();
    final session = _sessionStarting(now.subtract(const Duration(minutes: 2)));

    await _reconciler(service, _MemoryLedger(), now).reconcile(
      snapshot: _snapshot(now, session),
      library: _library(now, session),
    );

    expect(service.scheduled.single.notifyAt, now);
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

UserLibraryState _library(DateTime now, ShootingSession session) =>
    UserLibraryState(
      watchedSessions: [
        WatchedShootingSession.create(
          session: session,
          snapshotId: 'fresh-snapshot',
          watchedAt: now.subtract(const Duration(minutes: 1)),
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
  const _Scheduled({required this.session, required this.notifyAt});
  final ShootingSession session;
  final DateTime notifyAt;
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
  }) async {
    scheduled.add(_Scheduled(session: session, notifyAt: notifyAt));
  }
}

class _MemoryLedger implements ShootingSessionNotificationLedger {
  Map<String, DateTime> value = {};

  @override
  Future<Map<String, DateTime>> read() async => Map.unmodifiable(value);

  @override
  Future<void> write(Map<String, DateTime> scheduled) async {
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
