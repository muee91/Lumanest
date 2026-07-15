import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/profile/presentation/environment_diagnostics.dart';
import 'package:luma_nest/src/features/profile/presentation/profile_page.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/features/profile/application/environment_privacy_service.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/features/profile/infrastructure/profile_preferences_store.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/library/infrastructure/user_library_store.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';

void main() {
  testWidgets('confirms before clearing environment data', (tester) async {
    final privacyService = _FakeEnvironmentPrivacyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
          environmentConsentStoreProvider.overrideWithValue(
            _GrantedConsentStore(),
          ),
          environmentPrivacyServiceProvider.overrideWithValue(privacyService),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pump();

    // After the profile refactor, the environment-data section sits below
    // photography, activity, device and AI sections. Scroll it into view
    // before interacting (the widget may otherwise be recycled off-screen).
    await tester.dragUntilVisible(
      find.text('停止并清除'),
      find.byType(Scrollable).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('停止并清除'));
    await tester.pumpAndSettle();
    expect(find.text('停止使用环境数据？'), findsOneWidget);
    expect(find.textContaining('不会删除收藏与路线'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '停止并清除'));
    await tester.pumpAndSettle();

    expect(privacyService.calls, 1);
    expect(find.text('环境数据已停止使用并清除'), findsOneWidget);
  });

  testWidgets(
    'exposes switches for dynamic background, reduce motion and reduce flashing',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentDiagnosticStatusProvider.overrideWithValue(
              EnvironmentDiagnosticStatus.operational,
            ),
          ],
          child: const MaterialApp(home: ProfilePage()),
        ),
      );

      expect(find.text('动态背景'), findsOneWidget);
      expect(find.text('减少动效'), findsOneWidget);
      expect(find.text('减少闪烁'), findsOneWidget);
    },
  );

  testWidgets('tapping the dynamic background switch flips the value', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    final dynamicSwitch = find.ancestor(
      of: find.text('动态背景'),
      matching: find.byType(SwitchListTile),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is SwitchListTile && widget.value == true,
      ),
      findsOneWidget,
      reason: 'ambient background defaults to enabled',
    );

    await tester.tap(dynamicSwitch);
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            widget.title is Text &&
            (widget.title as Text).data == '动态背景' &&
            widget.value == false,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'profile controls update state and persist the final preferences',
    (tester) async {
      final store = _FakeProfilePreferencesStore();
      final container = ProviderContainer(
        overrides: [profilePreferencesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProfilePage()),
        ),
      );
      await tester.pump();

      final scrollable = find.byType(Scrollable).first;

      await tester.dragUntilVisible(
        find.text('风光'),
        scrollable,
        const Offset(0, -100),
      );
      await tester.tap(find.text('风光'));
      await tester.pump();

      await tester.dragUntilVisible(
        find.text('自驾'),
        scrollable,
        const Offset(0, -100),
      );
      await tester.tap(find.text('自驾'));
      await tester.pump();

      await tester.dragUntilVisible(
        find.byType(TextField),
        scrollable,
        const Offset(0, -100),
      );
      await tester.enterText(find.byType(TextField), '相机、35mm、三脚架');
      await tester.pump();

      final detailedTone = find.text('详细');
      await tester.dragUntilVisible(
        detailedTone,
        scrollable,
        const Offset(0, -100),
      );
      await tester.ensureVisible(detailedTone);
      await tester.pumpAndSettle();
      await tester.tap(detailedTone);
      await tester.pump();

      await tester.dragUntilVisible(
        find.byType(Slider),
        scrollable,
        const Offset(0, -100),
      );
      final slider = find.byType(Slider);
      final sliderCenter = tester.getCenter(slider);
      final sliderWidth = tester.getSize(slider).width;
      await tester.tapAt(sliderCenter + Offset(sliderWidth * 0.3, 0));
      await tester.pump();

      final state = container.read(profilePreferencesProvider);
      final renderedSliderValue = tester.widget<Slider>(slider).value;
      expect(state.photographyPreferences, contains('风光'));
      expect(state.activityPreferences, contains('自驾'));
      expect(state.equipmentList, '相机、35mm、三脚架');
      expect(state.aiTone, AiTone.detailed);
      expect(state.recommendationIntensity, greaterThan(0.5));
      expect(renderedSliderValue, state.recommendationIntensity);
      expect(store.value, state);
      expect(store.writeCount, greaterThanOrEqualTo(5));
    },
  );

  testWidgets('explains every external data source and its limitation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    // The data-sources entry is below the fold after the refactor added
    // photography, activity, device and AI sections. Scroll it into view
    // first because it may not be built yet (off the cache extent).
    await tester.dragUntilVisible(
      find.text('数据来源与使用说明'),
      find.byType(Scrollable).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();

    final entry = find.text('数据来源与使用说明');
    await tester.tap(entry.first);
    await tester.pumpAndSettle();

    expect(find.text('天气 · 和风天气'), findsOneWidget);
    expect(find.text('地图与路线 · 高德地图'), findsOneWidget);
    expect(find.text('路线高程 · Open-Meteo'), findsOneWidget);
    expect(find.text('野生动物 · GBIF'), findsOneWidget);
    expect(find.textContaining('不代表实时位置'), findsOneWidget);
    expect(find.textContaining('不替代专业测绘'), findsOneWidget);
  });

  testWidgets(
    'does not render empty groups for unavailable collections, routes or devices',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentDiagnosticStatusProvider.overrideWithValue(
              EnvironmentDiagnosticStatus.operational,
            ),
          ],
          child: const MaterialApp(home: ProfilePage()),
        ),
      );

      expect(
        find.text('我的收藏'),
        findsNothing,
        reason: 'collections group must not render when empty',
      );
      expect(
        find.text('已保存路线'),
        findsNothing,
        reason: 'routes group must not render when empty',
      );
      expect(
        find.text('已连接设备'),
        findsNothing,
        reason: 'devices group must not render when empty',
      );
      expect(
        find.text('暂无收藏'),
        findsNothing,
        reason: 'no empty-state placeholders for collections',
      );
      expect(
        find.text('暂无路线'),
        findsNothing,
        reason: 'no empty-state placeholders for routes',
      );
      expect(
        find.text('暂无设备'),
        findsNothing,
        reason: 'no empty-state placeholders for devices',
      );
    },
  );

  testWidgets('shows imported GPX tracks as local profile data', (
    tester,
  ) async {
    final track = ImportedRouteTrack(
      id: 'profile-track',
      name: '林间徒步线',
      importedAt: DateTime.utc(2026, 7, 15),
      points: const [
        GeoPoint(latitude: 30, longitude: 120),
        GeoPoint(latitude: 30.1, longitude: 120.1),
      ],
      distanceMeters: 1000,
      durationSeconds: 600,
      durationEstimated: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
          userLibraryStoreProvider.overrideWithValue(
            _ProfileLibraryStore(UserLibraryState(importedTracks: [track])),
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('林间徒步线'),
      find.byType(Scrollable).first,
      const Offset(0, -100),
    );

    expect(find.text('本地轨迹'), findsOneWidget);
    expect(find.text('林间徒步线'), findsOneWidget);
    expect(find.text('GPX · 仅保存在本机'), findsOneWidget);
  });

  testWidgets('shows no environment diagnostic when fully operational', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.operational,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('配置'), findsNothing);
    expect(find.textContaining('权限'), findsNothing);
    expect(find.textContaining('缓存'), findsNothing);
    // Switches are still present — the page rendered without diagnostics.
    expect(find.text('动态背景'), findsOneWidget);
  });

  testWidgets('shows QWeather config missing diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.qweatherConfigMissing,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.text('天气配置未完成，无法获取实时天气'), findsOneWidget);
  });

  testWidgets('shows AMap config missing diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.amapConfigMissing,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.text('地图配置未完成，无法显示探索地图'), findsOneWidget);
  });

  testWidgets('shows location permission denied diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.locationPermissionDenied,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('定位权限'), findsOneWidget);
  });

  testWidgets('shows stale cache diagnostic', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.staleCache,
          ),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(find.textContaining('缓存'), findsOneWidget);
  });

  testWidgets(
    'renders a live recovery action by default when diagnostics need one',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentDiagnosticStatusProvider.overrideWithValue(
              EnvironmentDiagnosticStatus.staleCache,
            ),
          ],
          child: const MaterialApp(home: ProfilePage()),
        ),
      );

      expect(
        find.textContaining('缓存'),
        findsOneWidget,
        reason: 'the diagnostic message must still render',
      );
      expect(find.text('重试'), findsOneWidget);
    },
  );

  testWidgets('tapping the retry button invokes an injected onRetry spy', (
    tester,
  ) async {
    var retryCalled = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.staleCache,
          ),
        ],
        child: MaterialApp(
          home: ProfilePage(
            actions: EnvironmentDiagnosticsActions(
              onRetry: () => retryCalled++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(retryCalled, 1);
  });

  testWidgets(
    'location service button invokes injected onOpenLocationSettings',
    (tester) async {
      var settingsCalled = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            environmentDiagnosticStatusProvider.overrideWithValue(
              EnvironmentDiagnosticStatus.locationServiceDisabled,
            ),
          ],
          child: MaterialApp(
            home: ProfilePage(
              actions: EnvironmentDiagnosticsActions(
                onOpenLocationSettings: () => settingsCalled++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开设置'));
      await tester.pump();

      expect(settingsCalled, 1);
    },
  );

  testWidgets('permission button invokes injected onOpenAppSettings', (
    tester,
  ) async {
    var settingsCalled = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentDiagnosticStatusProvider.overrideWithValue(
            EnvironmentDiagnosticStatus.locationPermissionDeniedForever,
          ),
        ],
        child: MaterialApp(
          home: ProfilePage(
            actions: EnvironmentDiagnosticsActions(
              onOpenAppSettings: () => settingsCalled++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开设置'));
    await tester.pump();

    expect(settingsCalled, 1);
  });

  testWidgets(
    'never renders sensitive key or host values in the profile page',
    (tester) async {
      const sensitiveTokens = <String>[
        'AMAP_ANDROID_KEY',
        'QWEATHER_API_HOST',
        'QWEATHER_TOKEN_ENDPOINT',
        'LUMANEST_SERVICE_TOKEN',
        'amapAndroidKey',
        'qweatherApiHost',
        'qweatherTokenEndpoint',
        'lumaNestServiceToken',
      ];

      for (final status in EnvironmentDiagnosticStatus.values) {
        if (status == EnvironmentDiagnosticStatus.operational) continue;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              environmentDiagnosticStatusProvider.overrideWithValue(status),
            ],
            child: const MaterialApp(home: ProfilePage()),
          ),
        );

        for (final token in sensitiveTokens) {
          expect(
            find.text(token),
            findsNothing,
            reason: '$token must not appear for status $status',
          );
          expect(
            find.textContaining(token),
            findsNothing,
            reason: '$token must not be a substring for status $status',
          );
        }
      }
    },
  );
}

class _FakeEnvironmentPrivacyService implements EnvironmentPrivacyService {
  var calls = 0;

  @override
  Future<void> revokeAndClear() async {
    calls += 1;
  }
}

class _GrantedConsentStore implements EnvironmentConsentStore {
  @override
  Future<bool?> readGranted() async => true;

  @override
  Future<void> writeGranted(bool granted) async {}
}

class _FakeProfilePreferencesStore implements ProfilePreferencesStore {
  ProfilePreferences? value;
  var writeCount = 0;

  @override
  Future<ProfilePreferences?> read() async => value;

  @override
  Future<void> write(ProfilePreferences value) async {
    writeCount += 1;
    this.value = value;
  }
}

class _ProfileLibraryStore implements UserLibraryStore {
  _ProfileLibraryStore(this.value);

  UserLibraryState value;

  @override
  Future<UserLibraryState> read() async => value;

  @override
  Future<void> write(UserLibraryState state) async => value = state;
}
