import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/notifications/application/route_reminder_service.dart';

void main() {
  test('does not schedule an already passed return time', () async {
    final now = DateTime.utc(2026, 7, 15, 8);
    final service = LocalRouteReminderService(now: () => now);

    final scheduled = await service.scheduleReturnReminder(
      journeyId: List.filled(64, 'a').join(),
      destinationName: '山谷步道',
      scheduledAt: now,
    );

    expect(scheduled, isFalse);
  });

  test('enables only after permission and persists the choice', () async {
    final service = _FakeRouteReminderService(permission: true);
    final store = _MemoryRouteReminderPreferenceStore();
    final container = ProviderContainer(
      overrides: [
        routeReminderServiceProvider.overrideWithValue(service),
        routeReminderPreferenceStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(routeReminderEnabledProvider.future), isFalse);

    final enabled = await container
        .read(routeReminderEnabledProvider.notifier)
        .setEnabled(true);

    expect(enabled, isTrue);
    expect(store.enabled, isTrue);
    expect(service.permissionRequests, 1);
  });

  test('denied permission leaves reminders disabled', () async {
    final service = _FakeRouteReminderService(permission: false);
    final store = _MemoryRouteReminderPreferenceStore();
    final container = ProviderContainer(
      overrides: [
        routeReminderServiceProvider.overrideWithValue(service),
        routeReminderPreferenceStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(routeReminderEnabledProvider.future);

    final enabled = await container
        .read(routeReminderEnabledProvider.notifier)
        .setEnabled(true);

    expect(enabled, isFalse);
    expect(store.enabled, isFalse);
  });

  test(
    'revoked system permission clears a previously enabled choice',
    () async {
      final service = _FakeRouteReminderService(permission: false);
      final store = _MemoryRouteReminderPreferenceStore(enabled: true);
      final container = ProviderContainer(
        overrides: [
          routeReminderServiceProvider.overrideWithValue(service),
          routeReminderPreferenceStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      expect(
        await container.read(routeReminderEnabledProvider.future),
        isFalse,
      );
      expect(store.enabled, isFalse);
    },
  );

  test('disabling cancels every pending return reminder', () async {
    final service = _FakeRouteReminderService(permission: true);
    final store = _MemoryRouteReminderPreferenceStore(enabled: true);
    final container = ProviderContainer(
      overrides: [
        routeReminderServiceProvider.overrideWithValue(service),
        routeReminderPreferenceStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(routeReminderEnabledProvider.future), isTrue);

    await container
        .read(routeReminderEnabledProvider.notifier)
        .setEnabled(false);

    expect(service.cancelAllCalls, 1);
    expect(store.enabled, isFalse);
  });
}

class _MemoryRouteReminderPreferenceStore
    implements RouteReminderPreferenceStore {
  _MemoryRouteReminderPreferenceStore({this.enabled = false});

  bool enabled;

  @override
  Future<bool> readEnabled() async => enabled;

  @override
  Future<void> writeEnabled(bool value) async => enabled = value;
}

class _FakeRouteReminderService implements RouteReminderService {
  _FakeRouteReminderService({required this.permission});

  final bool permission;
  var permissionRequests = 0;
  var cancelAllCalls = 0;

  @override
  Future<void> cancel(String journeyId) async {}

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<bool> permissionGranted() async => permission;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<bool> scheduleReturnReminder({
    required String journeyId,
    required String destinationName,
    required DateTime scheduledAt,
  }) async => true;
}
