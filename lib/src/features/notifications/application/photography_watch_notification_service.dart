import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/context/context_snapshot.dart';
import '../../../core/photography/shooting_session.dart';
import '../../library/domain/user_library.dart';

@immutable
class ShootingDeparturePlan {
  const ShootingDeparturePlan({
    required this.sessionId,
    this.targetId,
    required this.departureDeadline,
    required this.routeDuration,
    required this.createdAt,
  });

  final String sessionId;
  final String? targetId;
  final DateTime departureDeadline;
  final Duration routeDuration;
  final DateTime createdAt;

  String get key =>
      '$sessionId:${targetId ?? ''}:${departureDeadline.toUtc().toIso8601String()}';

  bool matches(WatchedShootingSession watch) {
    if (watch.sessionId != sessionId) return false;
    final plannedTarget = targetId;
    return plannedTarget == null
        ? watch.targetId == null
        : watch.targetId == plannedTarget;
  }
}

@immutable
class ShootingDeparturePlanInvalidation {
  const ShootingDeparturePlanInvalidation({
    required this.sessionId,
    this.targetId,
  });

  final String sessionId;
  final String? targetId;

  String get key => '$sessionId:${targetId ?? ''}';

  bool matches(WatchedShootingSession watch) {
    if (watch.sessionId != sessionId) return false;
    final invalidatedTarget = targetId;
    return invalidatedTarget == null
        ? watch.targetId == null
        : watch.targetId == invalidatedTarget;
  }
}

class ShootingDeparturePlanInvalidationController
    extends Notifier<ShootingDeparturePlanInvalidation?> {
  @override
  ShootingDeparturePlanInvalidation? build() => null;

  void mark(ShootingDeparturePlanInvalidation invalidation) {
    if (state?.key == invalidation.key) return;
    state = invalidation;
  }

  void clear() => state = null;
}

final shootingDeparturePlanInvalidationProvider = NotifierProvider<
  ShootingDeparturePlanInvalidationController,
  ShootingDeparturePlanInvalidation?
>(ShootingDeparturePlanInvalidationController.new);

class ShootingDeparturePlanController extends Notifier<ShootingDeparturePlan?> {
  @override
  ShootingDeparturePlan? build() => null;

  void setPlan(ShootingDeparturePlan plan) {
    ref.read(shootingDeparturePlanInvalidationProvider.notifier).clear();
    if (state?.key == plan.key) return;
    state = plan;
  }

  void clearFor(String sessionId, {String? targetId}) {
    if (state?.sessionId == sessionId) state = null;
    ref
        .read(shootingDeparturePlanInvalidationProvider.notifier)
        .mark(
          ShootingDeparturePlanInvalidation(
            sessionId: sessionId,
            targetId: targetId,
          ),
        );
  }
}

final shootingDeparturePlanProvider =
    NotifierProvider<ShootingDeparturePlanController, ShootingDeparturePlan?>(
      ShootingDeparturePlanController.new,
    );

/// Local-only reminders for shooting sessions the user explicitly chose to watch.
///
/// This service deliberately has no network, location, or background-refresh
/// behaviour. A caller must reconcile it with a freshly established snapshot.
abstract interface class ShootingSessionNotificationService {
  Future<bool> requestPermission();
  Future<bool> permissionGranted();
  Future<void> schedule({
    required WatchedShootingSession watch,
    required ShootingSession session,
    required DateTime notifyAt,
    required DateTime dataObservedAt,
    DateTime? departureDeadline,
  });
  Future<void> cancel(String watchId);
}

class LocalShootingSessionNotificationService
    implements ShootingSessionNotificationService {
  LocalShootingSessionNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initializing;
  void Function(String payload)? _onNotificationResponse;

  /// Must be registered by the foreground app before scheduling. The payload
  /// contains only an internal route plus a server-established session and optional target ID.
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
    required WatchedShootingSession watch,
    required ShootingSession session,
    required DateTime notifyAt,
    required DateTime dataObservedAt,
    DateTime? departureDeadline,
  }) async {
    await _ensureInitialized();
    final instant = notifyAt.toUtc();
    final body = reasonFor(
      session,
      dataObservedAt,
      departureDeadline: departureDeadline,
    );
    final isDepartureReminder = departureDeadline != null;
    if (!instant.isAfter(DateTime.now().toUtc())) {
      await _plugin.show(
        id: _notificationId(watch.id),
        title: isDepartureReminder
            ? '现在该出发：${session.title}'
            : '现在可以留意 ${session.title}',
        body: body,
        notificationDetails: _details,
        payload: shootingSessionNotificationPayloadFor(
          session.id,
          targetId: watch.targetId,
        ),
      );
      return;
    }
    await _plugin.zonedSchedule(
      id: _notificationId(watch.id),
      scheduledDate: tz.TZDateTime.from(instant, tz.UTC),
      title: isDepartureReminder
          ? '${session.title} 出发提醒'
          : '${session.title} 即将开始',
      body: body,
      notificationDetails: _details,
      payload: shootingSessionNotificationPayloadFor(
        session.id,
        targetId: watch.targetId,
      ),
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

  /// A reminder is the app speaking first, so it states only what the evidence
  /// supports: when the window opens, the conditions that make it, and how old
  /// that judgement is. It never asserts a success rate.
  @visibleForTesting
  static String reasonFor(
    ShootingSession session,
    DateTime dataObservedAt, {
    DateTime? departureDeadline,
  }) {
    final conditions = session.factors
        .where((item) => item.effect == ShootingFactorEffect.supporting)
        .map((item) => '${item.label} ${item.value}'.trim())
        .where((item) => item.isNotEmpty)
        .take(2)
        .join(' · ');
    return <String>[
      departureDeadline == null
          ? '窗口 ${_clock(session.startsAt)} 开始'
          : '最晚 ${_clock(departureDeadline)} 出发',
      if (conditions.isNotEmpty) '成立条件：$conditions',
      '依据 ${_clock(dataObservedAt)} 的数据',
    ].join(' · ');
  }

  static String _clock(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static int _notificationId(String watchId) {
    var value = 17;
    for (final codeUnit in watchId.codeUnits) {
      value = 0x1fffffff & (value * 31 + codeUnit);
    }
    return 0x40000000 | value;
  }
}

String shootingSessionNotificationPayloadFor(
  String sessionId, {
  String? targetId,
}) {
  final path = '/session/${Uri.encodeComponent(sessionId)}';
  if (targetId == null || targetId.isEmpty) return path;
  return Uri(path: path, queryParameters: {'target': targetId}).toString();
}

/// Wires only the local implementation to the app router. Keeping this out of
/// the scheduling interface lets deterministic notification tests use a small
/// fake service and keeps route handling out of the persistence layer.
void configureShootingSessionNotificationNavigation(
  ShootingSessionNotificationService service,
  void Function(String payload) handler,
) {
  if (service case LocalShootingSessionNotificationService local) {
    local.setNotificationResponseHandler(handler);
  }
}

abstract interface class ShootingSessionNotificationPreferenceStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool value);
}

class SharedPreferencesShootingSessionNotificationPreferenceStore
    implements ShootingSessionNotificationPreferenceStore {
  SharedPreferencesShootingSessionNotificationPreferenceStore(this._prefs);

  static const _key = 'shooting_session_notification_enabled';
  final SharedPreferencesAsync _prefs;

  @override
  Future<bool> readEnabled() async => await _prefs.getBool(_key) ?? false;

  @override
  Future<void> writeEnabled(bool value) => _prefs.setBool(_key, value);
}

/// A local schedule ledger. It stores notification timestamps only, never a
/// location, evidence payload, or session content.
abstract interface class ShootingSessionNotificationLedger {
  Future<Map<String, DateTime>> read();
  Future<void> write(Map<String, DateTime> scheduled);
}

class SharedPreferencesShootingSessionNotificationLedger
    implements ShootingSessionNotificationLedger {
  SharedPreferencesShootingSessionNotificationLedger(this._prefs);

  static const _key = 'shooting_session_notification_schedule';
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
class ShootingSessionNotificationReconciler {
  ShootingSessionNotificationReconciler({
    required this.service,
    required this.preferences,
    required this.ledger,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ShootingSessionNotificationService service;
  final ShootingSessionNotificationPreferenceStore preferences;
  final ShootingSessionNotificationLedger ledger;
  final DateTime Function() _now;

  Future<void> reconcile({
    required ContextSnapshot? snapshot,
    required UserLibraryState? library,
    ShootingDeparturePlan? departurePlan,
    ShootingDeparturePlanInvalidation? departureInvalidation,
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
      final sessions = {
        for (final item in snapshot.shootingSessions) item.id: item,
      };
      for (final watch in library.watchedSessions) {
        final session = sessions[watch.sessionId];
        if (session == null ||
            !watch.expiresAt.toUtc().isAfter(now) ||
            !session.endsAt.toUtc().isAfter(now)) {
          continue;
        }
        final matchedDeparturePlan =
            departurePlan != null && departurePlan.matches(watch)
            ? departurePlan
            : null;
        final explicitlyInvalidated =
            departureInvalidation?.matches(watch) ?? false;
        final fallbackNotifyAt = _notificationTime(session, now, null);
        final previousNotifyAt = existing[watch.id];
        // A route-derived deadline may already be scheduled by the OS. The
        // in-memory route plan intentionally does not survive process death;
        // when the app restarts without that transient plan, do not silently
        // cancel an earlier still-future departure reminder and downgrade it
        // to the generic 15-minute window reminder.
        final preservedDepartureNotifyAt =
            matchedDeparturePlan == null &&
                !explicitlyInvalidated &&
                previousNotifyAt != null &&
                previousNotifyAt.isAfter(now) &&
                previousNotifyAt.isBefore(fallbackNotifyAt)
            ? previousNotifyAt
            : null;
        final notifyAt = matchedDeparturePlan == null
            ? preservedDepartureNotifyAt ?? fallbackNotifyAt
            : _notificationTime(
                session,
                now,
                matchedDeparturePlan.departureDeadline,
              );
        valid[watch.id] = _WatchPlan(
          watch: watch,
          session: session,
          notifyAt: notifyAt,
          dataObservedAt: snapshot.observedAt,
          departureDeadline: matchedDeparturePlan?.departureDeadline,
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
      if (previous == null ||
          !previous.isAtSameMomentAs(plan.notifyAt)) {
        if (previous != null) await service.cancel(entry.key);
        await service.schedule(
          watch: plan.watch,
          session: plan.session,
          notifyAt: plan.notifyAt,
          dataObservedAt: plan.dataObservedAt,
          departureDeadline: plan.departureDeadline,
        );
      }
      next[entry.key] = plan.notifyAt;
    }
    await ledger.write(next);
  }

  static DateTime _notificationTime(
    ShootingSession session,
    DateTime now,
    DateTime? departureDeadline,
  ) {
    final candidate = departureDeadline?.toUtc() ??
        session.startsAt.toUtc().subtract(const Duration(minutes: 15));
    return candidate.isAfter(now) ? candidate : now;
  }
}

class _WatchPlan {
  const _WatchPlan({
    required this.watch,
    required this.session,
    required this.notifyAt,
    required this.dataObservedAt,
    this.departureDeadline,
  });

  final WatchedShootingSession watch;
  final ShootingSession session;
  final DateTime notifyAt;
  final DateTime dataObservedAt;
  final DateTime? departureDeadline;
}

final shootingSessionNotificationServiceProvider =
    Provider<ShootingSessionNotificationService>((ref) {
      return LocalShootingSessionNotificationService();
    });

final shootingSessionNotificationPreferenceStoreProvider =
    Provider<ShootingSessionNotificationPreferenceStore>((ref) {
      return SharedPreferencesShootingSessionNotificationPreferenceStore(
        SharedPreferencesAsync(),
      );
    });

final shootingSessionNotificationLedgerProvider =
    Provider<ShootingSessionNotificationLedger>((ref) {
      return SharedPreferencesShootingSessionNotificationLedger(
        SharedPreferencesAsync(),
      );
    });

final shootingSessionNotificationReconcilerProvider =
    Provider<ShootingSessionNotificationReconciler>((ref) {
      return ShootingSessionNotificationReconciler(
        service: ref.watch(shootingSessionNotificationServiceProvider),
        preferences: ref.watch(
          shootingSessionNotificationPreferenceStoreProvider,
        ),
        ledger: ref.watch(shootingSessionNotificationLedgerProvider),
      );
    });

class ShootingSessionNotificationController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final enabled = await ref
        .read(shootingSessionNotificationPreferenceStoreProvider)
        .readEnabled();
    if (!enabled) return false;
    final granted = await ref
        .read(shootingSessionNotificationServiceProvider)
        .permissionGranted();
    if (granted) return true;
    await ref
        .read(shootingSessionNotificationPreferenceStoreProvider)
        .writeEnabled(false);
    return false;
  }

  Future<bool> setEnabled(bool value) async {
    final service = ref.read(shootingSessionNotificationServiceProvider);
    if (value && !await service.requestPermission()) {
      await ref
          .read(shootingSessionNotificationPreferenceStoreProvider)
          .writeEnabled(false);
      state = const AsyncData(false);
      return false;
    }
    await ref
        .read(shootingSessionNotificationPreferenceStoreProvider)
        .writeEnabled(value);
    state = AsyncData(value);
    return value;
  }
}

final shootingSessionNotificationsEnabledProvider =
    AsyncNotifierProvider<ShootingSessionNotificationController, bool>(
      ShootingSessionNotificationController.new,
    );
