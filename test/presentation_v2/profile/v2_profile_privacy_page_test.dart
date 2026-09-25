import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/presentation_v2/profile/v2_profile_page.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

class _FixturePreferencesController extends ProfilePreferencesController {
  @override
  ProfilePreferences build() => const ProfilePreferences();
}

class _FixtureNotificationController
    extends ShootingSessionNotificationController {
  _FixtureNotificationController({this.initialEnabled = false});

  final bool initialEnabled;
  final List<bool> setEnabledCalls = <bool>[];

  @override
  Future<bool> build() async => initialEnabled;

  @override
  Future<bool> setEnabled(bool value) async {
    setEnabledCalls.add(value);
    return value;
  }
}

class _PendingNotificationController
    extends ShootingSessionNotificationController {
  final List<bool> setEnabledCalls = <bool>[];

  @override
  Future<bool> build() => Completer<bool>().future;

  @override
  Future<bool> setEnabled(bool value) async {
    setEnabledCalls.add(value);
    return value;
  }
}

Finder _notificationToggle() => find.ancestor(
  of: find.text('拍摄关注提醒'),
  matching: find.byType(V2Pressable),
);

Future<void> _pumpPrivacyPage(
  WidgetTester tester, {
  required ShootingSessionNotificationController notificationController,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profilePreferencesProvider.overrideWith(
          _FixturePreferencesController.new,
        ),
        shootingSessionNotificationsEnabledProvider.overrideWith(
          () => notificationController,
        ),
      ],
      child: const MaterialApp(home: V2ProfilePrivacyPage()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('关闭状态下点击开关会请求开启拍摄关注提醒', (tester) async {
    final controller = _FixtureNotificationController();
    await _pumpPrivacyPage(tester, notificationController: controller);

    expect(find.text('为你关注的拍摄窗口在本机安排提醒；只使用系统通知，不联网、不上报位置。'), findsOneWidget);

    await tester.tap(_notificationToggle());
    await tester.pump();

    expect(controller.setEnabledCalls, <bool>[true]);
  });

  testWidgets('开启状态下点击开关会发送关闭指令', (tester) async {
    final controller = _FixtureNotificationController(initialEnabled: true);
    await _pumpPrivacyPage(tester, notificationController: controller);

    await tester.tap(_notificationToggle());
    await tester.pump();

    expect(controller.setEnabledCalls, <bool>[false]);
  });

  testWidgets('偏好尚未恢复时点击开关不发出任何指令', (tester) async {
    final controller = _PendingNotificationController();
    await _pumpPrivacyPage(tester, notificationController: controller);

    await tester.tap(_notificationToggle());
    await tester.pump();

    expect(controller.setEnabledCalls, isEmpty);
  });
}
