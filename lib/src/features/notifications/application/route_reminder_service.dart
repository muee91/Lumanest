import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

abstract interface class RouteReminderService {
  Future<bool> requestPermission();
  Future<bool> permissionGranted();
  Future<bool> scheduleReturnReminder({
    required String journeyId,
    required String destinationName,
    required DateTime scheduledAt,
  });
  Future<void> cancel(String journeyId);
  Future<void> cancelAll();
}

class LocalRouteReminderService implements RouteReminderService {
  LocalRouteReminderService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       now = now ?? DateTime.now;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() now;
  Future<void>? _initializing;

  Future<void> _ensureInitialized() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification_lumanest'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<bool> permissionGranted() async {
    await _ensureInitialized();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions())
              ?.isEnabled ??
          false;
    }
    return false;
  }

  @override
  Future<bool> scheduleReturnReminder({
    required String journeyId,
    required String destinationName,
    required DateTime scheduledAt,
  }) async {
    final instant = scheduledAt.toUtc();
    if (!instant.isAfter(now().toUtc().add(const Duration(minutes: 1)))) {
      return false;
    }
    await _ensureInitialized();
    await _plugin.zonedSchedule(
      id: _notificationId(journeyId),
      scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
      title: '该准备返程了',
      body: '从“$destinationName”按当前路线返程，更有机会在日落前返回。',
      payload: '/route',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'hiking_return_reminders',
          '徒步返程提醒',
          channelDescription: '按当前路线和日落时间提醒开始返程',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }

  @override
  Future<void> cancel(String journeyId) async {
    await _ensureInitialized();
    await _plugin.cancel(id: _notificationId(journeyId));
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }

  static int _notificationId(String journeyId) {
    final prefix = journeyId.length >= 8
        ? journeyId.substring(0, 8)
        : journeyId.padRight(8, '0');
    return (int.tryParse(prefix, radix: 16) ?? journeyId.hashCode) & 0x7fffffff;
  }
}

abstract interface class RouteReminderPreferenceStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool value);
}

class SharedPreferencesRouteReminderPreferenceStore
    implements RouteReminderPreferenceStore {
  SharedPreferencesRouteReminderPreferenceStore(this._preferences);

  static const _key = 'hiking_return_reminder_enabled';
  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> readEnabled() async => await _preferences.getBool(_key) ?? false;

  @override
  Future<void> writeEnabled(bool value) => _preferences.setBool(_key, value);
}

final routeReminderServiceProvider = Provider<RouteReminderService>((ref) {
  return LocalRouteReminderService();
});

final routeReminderPreferenceStoreProvider =
    Provider<RouteReminderPreferenceStore>((ref) {
      return SharedPreferencesRouteReminderPreferenceStore(
        SharedPreferencesAsync(),
      );
    });

class RouteReminderController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final store = ref.read(routeReminderPreferenceStoreProvider);
    final enabled = await store.readEnabled();
    if (!enabled) return false;
    final granted = await ref
        .read(routeReminderServiceProvider)
        .permissionGranted();
    if (granted) return true;
    await store.writeEnabled(false);
    return false;
  }

  Future<bool> setEnabled(bool value) async {
    if (value) {
      final granted = await ref
          .read(routeReminderServiceProvider)
          .requestPermission();
      if (!granted) {
        await ref
            .read(routeReminderPreferenceStoreProvider)
            .writeEnabled(false);
        state = const AsyncData(false);
        return false;
      }
    } else {
      await ref.read(routeReminderServiceProvider).cancelAll();
    }
    await ref.read(routeReminderPreferenceStoreProvider).writeEnabled(value);
    state = AsyncData(value);
    return value;
  }
}

final routeReminderEnabledProvider =
    AsyncNotifierProvider<RouteReminderController, bool>(
      RouteReminderController.new,
    );
