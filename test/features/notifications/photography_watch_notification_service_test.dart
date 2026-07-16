import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/photography/photography_opportunity.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';

void main() {
  test('notification payload targets only its established opportunity', () {
    expect(
      photographyWatchNotificationPayloadFor('photo-blue-hour'),
      '/shooting-window?opportunity=photo-blue-hour',
    );
  });

  final now = DateTime.utc(2026, 7, 17, 10);

  test(
    'schedules one explicit future watch fifteen minutes before start',
    () async {
      final service = _FakeService();
      final ledger = _MemoryLedger();
      final reconciler = _reconciler(service, ledger, now);
      final opportunity = _opportunity(
        startsAt: now.add(const Duration(minutes: 35)),
      );

      await reconciler.reconcile(
        snapshot: _snapshot(now, opportunity),
        library: _library(now, opportunity),
      );

      expect(service.scheduled, hasLength(1));
      expect(
        service.scheduled.single.notifyAt,
        now.add(const Duration(minutes: 20)),
      );
      expect(service.scheduled.single.opportunity.id, opportunity.id);
    },
  );

  test('uses a single immediate notification for a current watch', () async {
    final service = _FakeService();
    final reconciler = _reconciler(service, _MemoryLedger(), now);
    final opportunity = _opportunity(
      startsAt: now.subtract(const Duration(minutes: 2)),
    );

    await reconciler.reconcile(
      snapshot: _snapshot(now, opportunity),
      library: _library(now, opportunity),
    );

    expect(service.scheduled.single.notifyAt, now);
  });

  test(
    'does not reschedule a watch when its notification timestamp is unchanged',
    () async {
      final service = _FakeService();
      final ledger = _MemoryLedger();
      final reconciler = _reconciler(service, ledger, now);
      final opportunity = _opportunity(
        startsAt: now.add(const Duration(minutes: 35)),
      );
      final snapshot = _snapshot(now, opportunity);
      final library = _library(now, opportunity);

      await reconciler.reconcile(snapshot: snapshot, library: library);
      await reconciler.reconcile(snapshot: snapshot, library: library);

      expect(service.scheduled, hasLength(1));
      expect(service.cancelled, isEmpty);
    },
  );

  test(
    'rejects stale snapshots and cancels their previous watch notification',
    () async {
      final service = _FakeService();
      final ledger = _MemoryLedger();
      final reconciler = _reconciler(service, ledger, now);
      final opportunity = _opportunity(
        startsAt: now.add(const Duration(minutes: 35)),
      );
      final library = _library(now, opportunity);

      await reconciler.reconcile(
        snapshot: _snapshot(now, opportunity),
        library: library,
      );
      await reconciler.reconcile(
        snapshot: _snapshot(now, opportunity, stale: true),
        library: library,
      );

      expect(service.scheduled, hasLength(1));
      expect(service.cancelled, [library.watchedOpportunities.single.id]);
      expect(await ledger.read(), isEmpty);
    },
  );

  test('expired or missing watched opportunities are cancelled', () async {
    final service = _FakeService();
    final ledger = _MemoryLedger();
    final reconciler = _reconciler(service, ledger, now);
    final opportunity = _opportunity(
      startsAt: now.add(const Duration(minutes: 35)),
    );
    final library = _library(now, opportunity);

    await reconciler.reconcile(
      snapshot: _snapshot(now, opportunity),
      library: library,
    );
    await reconciler.reconcile(
      snapshot: _snapshot(now, null),
      library: library,
    );

    expect(service.cancelled, [library.watchedOpportunities.single.id]);
  });

  test('permission-denied preference cannot be enabled', () async {
    final service = _FakeService(permission: false);
    final preference = _MemoryPreference();
    final container = ProviderContainer(
      overrides: [
        photographyWatchNotificationServiceProvider.overrideWithValue(service),
        photographyWatchNotificationPreferenceStoreProvider.overrideWithValue(
          preference,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(photographyWatchNotificationsEnabledProvider.future);

    final enabled = await container
        .read(photographyWatchNotificationsEnabledProvider.notifier)
        .setEnabled(true);

    expect(enabled, isFalse);
    expect(preference.enabled, isFalse);
    expect(service.permissionRequests, 1);
  });
}

PhotographyWatchNotificationReconciler _reconciler(
  _FakeService service,
  _MemoryLedger ledger,
  DateTime now,
) => PhotographyWatchNotificationReconciler(
  service: service,
  preferences: _MemoryPreference(enabled: true),
  ledger: ledger,
  now: () => now,
);

PhotographyOpportunity _opportunity({required DateTime startsAt}) =>
    PhotographyOpportunity(
      id: 'sunset-watch',
      title: '晚霞窗口',
      startsAt: startsAt,
      peaksAt: startsAt.add(const Duration(minutes: 10)),
      expiresAt: startsAt.add(const Duration(minutes: 30)),
      confidence: .8,
      evidence: const [
        PhotographyEvidence(
          id: 'weather',
          kind: PhotographyEvidenceKind.weather,
          statement: '西侧云隙正在打开',
          confidence: .8,
        ),
      ],
    );

ContextSnapshot _snapshot(
  DateTime now,
  PhotographyOpportunity? opportunity, {
  bool stale = false,
}) => ContextSnapshot(
  id: 'fresh-snapshot',
  observedAt: now,
  expiresAt: now.add(const Duration(minutes: 15)),
  primaryScene: SceneType.city,
  dayPhase: DayPhase.sunset,
  weather: WeatherType.cloudy,
  activeRoute: false,
  isStale: stale,
  photographyOpportunities: opportunity == null ? const [] : [opportunity],
);

UserLibraryState _library(DateTime now, PhotographyOpportunity opportunity) =>
    UserLibraryState(
      watchedOpportunities: [
        WatchedPhotographyOpportunity.create(
          opportunityId: opportunity.id,
          snapshotId: 'fresh-snapshot',
          title: opportunity.title,
          watchedAt: now.subtract(const Duration(minutes: 1)),
          expiresAt: opportunity.expiresAt,
        ),
      ],
    );

class _FakeService implements PhotographyWatchNotificationService {
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
    permissionRequests++;
    return permission;
  }

  @override
  Future<void> schedule({
    required WatchedPhotographyOpportunity watch,
    required PhotographyOpportunity opportunity,
    required DateTime notifyAt,
  }) async {
    scheduled.add(_Scheduled(watch, opportunity, notifyAt));
  }
}

class _Scheduled {
  const _Scheduled(this.watch, this.opportunity, this.notifyAt);

  final WatchedPhotographyOpportunity watch;
  final PhotographyOpportunity opportunity;
  final DateTime notifyAt;
}

class _MemoryPreference implements PhotographyWatchNotificationPreferenceStore {
  _MemoryPreference({this.enabled = false});

  bool enabled;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;
}

class _MemoryLedger implements PhotographyWatchNotificationLedger {
  Map<String, DateTime> values = {};

  @override
  Future<Map<String, DateTime>> read() async => Map.of(values);

  @override
  Future<void> write(Map<String, DateTime> scheduled) async {
    values = Map.of(scheduled);
  }
}
