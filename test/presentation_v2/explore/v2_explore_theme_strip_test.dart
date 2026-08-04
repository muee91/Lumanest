import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/config/environment_config.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/application/map_consent_controller.dart';
import 'package:luma_nest/src/features/explore/application/nearby_place_providers.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/infrastructure/amap_initializer.dart';
import 'package:luma_nest/src/presentation_v2/explore/v2_explore_page.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';

import '../../features/explore/map_consent_test_harness.dart';

void main() {
  testWidgets(
    'a short expanded result panel scrolls its lead and results without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [
          environmentConfigProvider.overrideWithValue(
            EnvironmentConfig(amapAndroidKey: 'test-key'),
          ),
          environmentConsentStoreProvider.overrideWithValue(
            _GrantedEnvironmentConsentStore(),
          ),
          mapConsentStoreProvider.overrideWithValue(
            FakeMapConsentStore(granted: true),
          ),
          amapInitializerGatewayProvider.overrideWithValue(
            FakeAmapInitializerGateway(),
          ),
          environmentSnapshotProvider.overrideWith(
            _FixedEnvironmentController.new,
          ),
          nearbyPlacesProvider.overrideWith((_) async => [_nearbyPlace]),
        ],
      );
      addTearDown(container.dispose);
      container.read(environmentConsentProvider.notifier).grant();
      await container
          .read(mapConsentControllerProvider.notifier)
          .grantConsent();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: V2ExplorePage()),
        ),
      );
      await tester.pump();
      await tester.pump();

      final panel = find.byKey(const Key('v2-explore-results-panel'));
      final gesture = await tester.startGesture(tester.getCenter(panel));
      await gesture.moveBy(const Offset(0, 210));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a partially expanded panel must scroll rather than overflow',
      );
      await gesture.up();
    },
  );

  testWidgets(
    'explore themes form one horizontal strip below search controls',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          environmentConfigProvider.overrideWithValue(
            EnvironmentConfig(amapAndroidKey: 'test-key'),
          ),
          environmentConsentStoreProvider.overrideWithValue(
            _GrantedEnvironmentConsentStore(),
          ),
          mapConsentStoreProvider.overrideWithValue(
            FakeMapConsentStore(granted: true),
          ),
          amapInitializerGatewayProvider.overrideWithValue(
            FakeAmapInitializerGateway(),
          ),
          environmentSnapshotProvider.overrideWith(
            _FixedEnvironmentController.new,
          ),
          nearbyPlacesProvider.overrideWith((_) async => const <NearbyPlace>[]),
        ],
      );
      addTearDown(container.dispose);
      container.read(environmentConsentProvider.notifier).grant();
      await container
          .read(mapConsentControllerProvider.notifier)
          .grantConsent();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: V2ExplorePage()),
        ),
      );
      await tester.pump();

      final strip = find.byKey(const Key('v2-explore-theme-strip'));
      final searchButton = find.byKey(const Key('v2-explore-search-button'));
      expect(strip, findsOneWidget);
      expect(searchButton, findsOneWidget);
      expect(
        tester.getTopLeft(strip).dy,
        greaterThan(tester.getBottomLeft(searchButton).dy),
      );
      expect(
        find.descendant(of: strip, matching: find.byType(Scrollable)),
        findsOneWidget,
      );
      final list = tester.widget<ListView>(
        find.descendant(of: strip, matching: find.byType(ListView)),
      );
      expect(list.scrollDirection, Axis.horizontal);
      expect(find.byKey(const Key('v2-explore-theme-context')), findsNothing);
      expect(
        find.byKey(const Key('v2-explore-theme-viewpoint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('v2-explore-theme-humanity')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('v2-explore-nearby-services')), findsNothing);
      await tester.drag(strip, const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('v2-explore-theme-supplies')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('v2-explore-theme-parking')), findsOneWidget);
      expect(find.byKey(const Key('v2-explore-theme-food')), findsOneWidget);
      expect(find.byKey(const Key('v2-explore-theme-fuel')), findsOneWidget);
      expect(find.byKey(const Key('v2-explore-theme-medical')), findsOneWidget);
      expect(find.text('选择探索主题'), findsNothing);
      expect(find.text('换一个探索主题'), findsNothing);
      expect(find.text('上拉查看'), findsOneWidget);

      final selectedMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const Key('v2-explore-theme-water')),
          matching: find.byType(Material),
        ),
      );
      expect(selectedMaterial.color, V2Palette.mossSoft);
      expect(selectedMaterial.color, isNot(V2Palette.night));

      await tester.tap(find.byKey(const Key('v2-explore-theme-food')));
      await tester.pump();

      expect(
        container.read(exploreIntentProvider).category,
        NearbyPlaceCategory.food,
      );

      await tester.tap(searchButton);
      await tester.pump();
      expect(find.text('快捷服务'), findsOneWidget);
      expect(find.text('景点'), findsNothing);
      expect(find.text('人文街巷'), findsNothing);
      expect(find.text('附近餐饮'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final resultsPanel = tester.widget<AnimatedPositioned>(
        find.byKey(const Key('v2-explore-results-panel')),
      );
      expect(resultsPanel.bottom, 320 / tester.view.devicePixelRatio);
    },
  );
}

const _nearbyPlace = NearbyPlace(
  id: 'overflow-regression-place',
  name: '江夏村牌坊与附近街巷',
  category: NearbyPlaceCategory.viewpoint,
  point: GeoPoint(latitude: 23.16, longitude: 113.27),
  distanceMeters: 1200,
  address: '白云区江夏北一路附近',
  sourceEvidenceCount: 2,
);

class _FixedEnvironmentController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() async => ContextFixtures.lakeSunset();
}

class _GrantedEnvironmentConsentStore implements EnvironmentConsentStore {
  @override
  Future<bool?> readGranted() async => true;

  @override
  Future<void> writeGranted(bool granted) async {}
}
