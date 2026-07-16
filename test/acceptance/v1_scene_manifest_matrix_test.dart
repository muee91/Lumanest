import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/manifest/manifest_action_resolver.dart';
import 'package:luma_nest/src/core/manifest/manifest_policy.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/features/inspiration/domain/inspiration_note.dart';

void main() {
  final cases = <_SceneCase>[
    _SceneCase(
      name: '城市',
      snapshot: ContextFixtures.quietCity(),
      scene: SceneType.city,
      creativeIds: const [],
      safetyIds: const [],
      layout: LayoutMode.quiet,
      routeMode: ContextRouteMode.none,
      routeStage: ContextRouteStage.none,
    ),
    _SceneCase(
      name: '湖泊',
      snapshot: ContextFixtures.lakeSunset(),
      scene: SceneType.lake,
      creativeIds: const ['reflection', 'blue-hour'],
      safetyIds: const [],
      layout: LayoutMode.opportunity,
      routeMode: ContextRouteMode.none,
      routeStage: ContextRouteStage.none,
    ),
    _SceneCase(
      name: '高山',
      snapshot: ContextFixtures.mountainDawn(),
      scene: SceneType.mountain,
      creativeIds: const ['alpenglow'],
      safetyIds: const [],
      layout: LayoutMode.opportunity,
      routeMode: ContextRouteMode.none,
      routeStage: ContextRouteStage.none,
    ),
    _SceneCase(
      name: '沙漠戈壁',
      snapshot: ContextFixtures.desertDusk(),
      scene: SceneType.desert,
      creativeIds: const ['dust-light'],
      safetyIds: const [],
      layout: LayoutMode.opportunity,
      routeMode: ContextRouteMode.none,
      routeStage: ContextRouteStage.none,
    ),
    _SceneCase(
      name: '村落人文',
      snapshot: ContextFixtures.villageMorning(),
      scene: SceneType.village,
      creativeIds: const ['humanity-light'],
      safetyIds: const [],
      layout: LayoutMode.opportunity,
      routeMode: ContextRouteMode.none,
      routeStage: ContextRouteStage.none,
    ),
    _SceneCase(
      name: '自驾',
      snapshot: ContextFixtures.drivingActiveRoute(),
      scene: SceneType.driving,
      creativeIds: const ['route-light-window'],
      safetyIds: const [],
      layout: LayoutMode.operation,
      routeMode: ContextRouteMode.driving,
      routeStage: ContextRouteStage.active,
    ),
    _SceneCase(
      name: '徒步',
      snapshot: ContextFixtures.hikingTrail(),
      scene: SceneType.hiking,
      creativeIds: const [],
      safetyIds: const ['hiking-return-check'],
      layout: LayoutMode.operation,
      routeMode: ContextRouteMode.hiking,
      routeStage: ContextRouteStage.active,
    ),
  ];

  group('V1 七类场景 Manifest 验收矩阵', () {
    for (final sceneCase in cases) {
      test('${sceneCase.name}：场景、通道、顺序和路线状态正确', () {
        final snapshot = sceneCase.snapshot;
        final manifest = ManifestPolicy.build(
          snapshot,
          now: snapshot.observedAt.add(const Duration(minutes: 1)),
        );

        expect(snapshot.primaryScene, sceneCase.scene);
        expect(snapshot.routeMode, sceneCase.routeMode);
        expect(snapshot.routeStage, sceneCase.routeStage);
        expect(
          snapshot.activeRoute,
          sceneCase.routeStage == ContextRouteStage.active,
        );
        expect(manifest.layoutMode, sceneCase.layout);
        expect(
          manifest.creativeItems.map((item) => item.id),
          sceneCase.creativeIds,
        );
        expect(manifest.safety.map((item) => item.id), sceneCase.safetyIds);
        expect(manifest.summary, isNotEmpty);
        expect(manifest.secondary, hasLength(lessThanOrEqualTo(2)));

        final notes = InspirationNotes.build(snapshot, manifest: manifest);
        final factualIds = notes
            .where((note) => note.isFactual)
            .map((note) => note.id);
        expect(
          factualIds,
          sceneCase.creativeIds.where((id) => id != 'regional-wildlife'),
        );
        expect(notes.where((note) => !note.isFactual), isNotEmpty);
        for (final safetyId in sceneCase.safetyIds) {
          expect(notes.map((note) => note.id), isNot(contains(safetyId)));
        }
        if (manifest.primary case final primary?) {
          if (primary.id != 'regional-wildlife') {
            expect(notes.first.id, primary.id);
          }
          expect(manifest.inspirationPreview, isNotEmpty);
        } else {
          expect(notes.where((note) => note.isFactual), isEmpty);
          expect(notes.where((note) => !note.isFactual), isNotEmpty);
          expect(manifest.inspirationPreview, isEmpty);
        }
      });

      test('${sceneCase.name}：结构化事件具有可追溯元数据和允许动作', () {
        final snapshot = sceneCase.snapshot;
        final declaredIds = {
          ...snapshot.opportunityIds,
          ...snapshot.safetyEventIds,
          ...snapshot.wildlifeEventIds,
        };

        expect(snapshot.events.map((event) => event.id).toSet(), declaredIds);
        for (final event in snapshot.events) {
          expect(event.expiresAt.isAfter(event.observedAt), isTrue);
          expect(event.confidence, inInclusiveRange(0, 1));
          expect(event.geoScope, isNotNull);
          expect(event.allowedAction, isNotNull);
          expect(snapshot.allowedActions, contains(event.allowedAction));
          if (_isSafety(event)) {
            expect(event.safetyLevel, isNotNull);
          } else {
            expect(event.safetyLevel, isNull);
          }
        }
      });

      test('${sceneCase.name}：事件到期后退场且动作不越过白名单', () {
        final snapshot = sceneCase.snapshot;
        final currentManifest = ManifestPolicy.build(
          snapshot,
          now: snapshot.observedAt.add(const Duration(minutes: 1)),
        );

        for (final item in [
          ...currentManifest.creativeItems,
          ...currentManifest.safety,
        ]) {
          final resolution = ManifestActionResolver.resolve(item);
          expect(
            [
              resolution.route,
              resolution.panel,
              resolution.externalUri,
            ].where((value) => value != null),
            hasLength(1),
          );
        }

        if (snapshot.events.isEmpty) return;
        final latestExpiry = snapshot.events
            .map((event) => event.expiresAt)
            .reduce((first, second) => first.isAfter(second) ? first : second);
        final expiredManifest = ManifestPolicy.build(
          snapshot,
          now: latestExpiry,
        );
        expect(expiredManifest.creativeItems, isEmpty);
        expect(expiredManifest.safety, isEmpty);
        expect(expiredManifest.inspirationPreview, isEmpty);
        final expiredNotes = InspirationNotes.build(
          snapshot,
          manifest: expiredManifest,
        );
        expect(expiredNotes.where((note) => note.isFactual), isEmpty);
        expect(expiredNotes.where((note) => !note.isFactual), isNotEmpty);
      });
    }
  });
}

bool _isSafety(ContextEvent event) =>
    event.channel == ContextEventChannel.safety ||
    event.channel == ContextEventChannel.wildlifeSafety;

class _SceneCase {
  const _SceneCase({
    required this.name,
    required this.snapshot,
    required this.scene,
    required this.creativeIds,
    required this.safetyIds,
    required this.layout,
    required this.routeMode,
    required this.routeStage,
  });

  final String name;
  final ContextSnapshot snapshot;
  final SceneType scene;
  final List<String> creativeIds;
  final List<String> safetyIds;
  final LayoutMode layout;
  final ContextRouteMode routeMode;
  final ContextRouteStage routeStage;
}
