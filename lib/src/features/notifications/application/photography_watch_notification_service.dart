import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/context/context_snapshot.dart';
import '../../../core/photography/photography_opportunity.dart';
import '../../library/domain/user_library.dart';

/// Local-only reminders for opportunities the user explicitly chose to watch.
///
/// This service deliberately has no network, location, or background-refresh
/// behaviour. A caller must reconcile it with a freshly established snapshot.
abstract interface class PhotographyWatchNotificationService {
  Future<bool> requestPermission();
  Future<bool> permissionGranted();
  Future<void> schedule({
    required WatchedPhotographyOpportunity watch,
    required PhotographyOpportunity opportunity,
    required DateTime notifyAt,
  });
  Future<void> cancel(String watchId);
}

class LocalPhotographyWatchNotificationService
    implements PhotographyWatchNotificationService {
  LocalPhotographyWatchNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initializing;
  void Function(String payload)? _onNotificationResponse;

  /// Must be registered by the foreground app before scheduling. The payload
  /// contains only an internal route plus a server-established opportunity ID.
  void setNotificationResponseHandler(void Function(String payload) handler) {
    _onNotificationResponse = handler;
  }

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
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _onNotificationResponse?.call(payload);
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchPayload != null) {
      _onNotificationResponse?.call(launchPayload);
    }
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
  Future<void> schedule({
    required WatchedPhotographyOpportunity watch,
    required PhotographyOpportunity opportunity,
    required DateTime notifyAt,
  }) async {
    await _ensureInitialized();
    final instant = notifyAt.toUtc();
    final body = _reason(opportunity);
    if (!instant.isAfter(DateTime.now().toUtc())) {
      await _plugin.show(
        id: _notificationId(watch.id),
        title: '现在可以留意 ${opportunity.title}',
        body: body,
        notificationDetails: _details,
        payload: photographyWatchNotificationPayloadFor(opportunity.id),
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: _notificationId(watch.id),
      scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
      title: '${opportunity.title} 即将开始',
      body: body,
      notificationDetails: _details,
      payload: photographyWatchNotificationPayloadFor(opportunity.id),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(String watchId) async {
    await _ensureInitialized();
    await _plugin.cancel(id: _notificationId(watchId));
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'photography_watch_reminders',
      '拍摄窗口提醒',
      channelDescription: '仅提醒你主动关注的已成立拍摄窗口',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static String _reason(PhotographyOpportunity opportunity) {
    final evidence = opportunity.evidence
        .where((item) => item.supports)
        .map((item) => item.statement.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '条件已成立');
    return evidence;
  }

  static int _notificationId(String watchId) {
    var value = 17;
    for (final codeUnit in watchId.codeUnits) {
      value = 0x1fffffff & (value * 31 + codeUnit);
    }
    return 0x40000000 | value;
  }
}

String photographyWatchNotificationPayloadFor(String opportunityId) => Uri(
  path: '/shooting-window',
  queryParameters: {'opportunity': opportunityId},
).toString();

/// Wires only the local implementation to the app router. Keeping this out of
/// the scheduling interface lets deterministic notification tests use a small
/// fake service and keeps route handling out of the persistence layer.
void configurePhotographyWatchNotificationNavigation(
  PhotographyWatchNotificationService service,
  void Function(String payload) handler,
) {
  if (service case LocalPhotographyWatchNotificationService local) {
    local.setNotificationResponseHandler(handler);
  }
}

abstract interface class PhotographyWatchNotificationPreferenceStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool value);
}

class SharedPreferencesPhotographyWatchNotificationPreferenceStore
    implements PhotographyWatchNotificationPreferenceStore {
  SharedPreferencesPhotographyWatchNotificationPreferenceStore(this._prefs);

  static const _key = 'photography_watch_notification_enabled';
  final SharedPreferencesAsync _prefs;

  @override
  Future<bool> readEnabled() async => await _prefs.getBool(_key) ?? false;

  @override
  Future<void> writeEnabled(bool value) => _prefs.setBool(_key, value);
}

/// A local schedule ledger. It stores notification timestamps only, never a
/// location, evidence payload, or opportunity content.
abstract interface class PhotographyWatchNotificationLedger {
  Future<Map<String, DateTime>> read();
  Future<void> write(Map<String, DateTime> scheduled);
}

class SharedPreferencesPhotographyWatchNotificationLedger
    implements PhotographyWatchNotificationLedger {
  SharedPreferencesPhotographyWatchNotificationLedger(this._prefs);

  static const _key = 'photography_watch_notification_schedule_v1';
  final SharedPreferencesAsync _prefs;

  @override
  Future<Map<String, DateTime>> read() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return const {};
    try {
      final values = jsonDecode(raw);
      if (values is! Map) return const {};
      final result = <String, DateTime>{};
      values.forEach((key, value) {
        if (key is! String || value is! String) return;
        final parsed = DateTime.tryParse(value)?.toUtc();
        if (parsed != null) result[key] = parsed;
      });
      return result;
    } on FormatException {
      return const {};
    }
  }

  @override
  Future<void> write(Map<String, DateTime> scheduled) {
    final encoded = scheduled.map(
      (key, value) => MapEntry(key, value.toUtc().toIso8601String()),
    );
    return _prefs.setString(_key, jsonEncode(encoded));
  }
}

/// Schedules only a user's explicit watches against a fresh snapshot.
///
/// Reconciliation is intentionally invoked by the app's foreground snapshot
/// refresh path; it does not register a background task or poll any provider.
class PhotographyWatchNotificationReconciler {
  PhotographyWatchNotificationReconciler({
    required this.service,
    required this.preferences,
    required this.ledger,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PhotographyWatchNotificationService service;
  final PhotographyWatchNotificationPreferenceStore preferences;
  final PhotographyWatchNotificationLedger ledger;
  final DateTime Function() _now;

  Future<void> reconcile({
    required ContextSnapshot? snapshot,
    required UserLibraryState? library,
  }) async {
    final existing = await ledger.read();
    final now = _now().toUtc();
    final enabled = await preferences.readEnabled();
    final fresh =
        snapshot != null &&
        !snapshot.isStale &&
        snapshot.expiresAt.toUtc().isAfter(now);
    final valid = <String, _WatchPlan>{};

    if (enabled &&
        fresh &&
        library != null &&
        await service.permissionGranted()) {
      final opportunities = {
        for (final item in snapshot.photographyOpportunities) item.id: item,
      };
      for (final watch in library.watchedOpportunities) {
        final opportunity = opportunities[watch.opportunityId];
        if (opportunity == null ||
            !watch.expiresAt.toUtc().isAfter(now) ||
            !opportunity.expiresAt.toUtc().isAfter(now)) {
          continue;
        }
        final notifyAt = _notificationTime(opportunity, now);
        valid[watch.id] = _WatchPlan(
          watch: watch,
          opportunity: opportunity,
          notifyAt: notifyAt,
        );
      }
    }

    for (final id in existing.keys.where((id) => !valid.containsKey(id))) {
      await service.cancel(id);
    }

    final next = <String, DateTime>{};
    for (final entry in valid.entries) {
      final previous = existing[entry.key];
      final plan = entry.value;
      if (previous == null || !previous.isAtSameMomentAs(plan.notifyAt)) {
        if (previous != null) await service.cancel(entry.key);
        await service.schedule(
          watch: plan.watch,
          opportunity: plan.opportunity,
          notifyAt: plan.notifyAt,
        );
      }
      next[entry.key] = plan.notifyAt;
    }
    await ledger.write(next);
  }

  static DateTime _notificationTime(
    PhotographyOpportunity opportunity,
    DateTime now,
  ) {
    final beforeStart = opportunity.startsAt.toUtc().subtract(
      const Duration(minutes: 15),
    );
    return beforeStart.isAfter(now) ? beforeStart : now;
  }
}

class _WatchPlan {
  const _WatchPlan({
    required this.watch,
    required this.opportunity,
    required this.notifyAt,
  });

  final WatchedPhotographyOpportunity watch;
  final PhotographyOpportunity opportunity;
  final DateTime notifyAt;
}

final photographyWatchNotificationServiceProvider =
    Provider<PhotographyWatchNotificationService>((ref) {
      return LocalPhotographyWatchNotificationService();
    });

final photographyWatchNotificationPreferenceStoreProvider =
    Provider<PhotographyWatchNotificationPreferenceStore>((ref) {
      return SharedPreferencesPhotographyWatchNotificationPreferenceStore(
        SharedPreferencesAsync(),
      );
    });

final photographyWatchNotificationLedgerProvider =
    Provider<PhotographyWatchNotificationLedger>((ref) {
      return SharedPreferencesPhotographyWatchNotificationLedger(
        SharedPreferencesAsync(),
      );
    });

final photographyWatchNotificationReconcilerProvider =
    Provider<PhotographyWatchNotificationReconciler>((ref) {
      return PhotographyWatchNotificationReconciler(
        service: ref.watch(photographyWatchNotificationServiceProvider),
        preferences: ref.watch(
          photographyWatchNotificationPreferenceStoreProvider,
        ),
        ledger: ref.watch(photographyWatchNotificationLedgerProvider),
      );
    });

class PhotographyWatchNotificationController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final enabled = await ref
        .read(photographyWatchNotificationPreferenceStoreProvider)
        .readEnabled();
    if (!enabled) return false;
    final granted = await ref
        .read(photographyWatchNotificationServiceProvider)
        .permissionGranted();
    if (granted) return true;
    await ref
        .read(photographyWatchNotificationPreferenceStoreProvider)
        .writeEnabled(false);
    return false;
  }

  Future<bool> setEnabled(bool value) async {
    final service = ref.read(photographyWatchNotificationServiceProvider);
    if (value && !await service.requestPermission()) {
      await ref
          .read(photographyWatchNotificationPreferenceStoreProvider)
          .writeEnabled(false);
      state = const AsyncData(false);
      return false;
    }
    await ref
        .read(photographyWatchNotificationPreferenceStoreProvider)
        .writeEnabled(value);
    state = AsyncData(value);
    return value;
  }
}

final photographyWatchNotificationsEnabledProvider =
    AsyncNotifierProvider<PhotographyWatchNotificationController, bool>(
      PhotographyWatchNotificationController.new,
    );
