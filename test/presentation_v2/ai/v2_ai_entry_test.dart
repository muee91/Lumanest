import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/companion/companion_client.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/presentation_v2/inspiration/v2_inspiration_page.dart';

void main() {
  testWidgets('AI entry is a text conversation without unsupported controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentSnapshotProvider.overrideWith(
            _FixedEnvironmentController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: V2InspirationPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('问栖光'), findsOneWidget);
    expect(find.text('摄影对话'), findsOneWidget);
    expect(find.text('发消息给栖光'), findsOneWidget);
    expect(find.text('想去哪里？'), findsNothing);
    expect(find.text('我可以帮你发现附近灵感、活动、路线'), findsNothing);
    expect(find.byIcon(CupertinoIcons.plus), findsNothing);
    expect(find.byIcon(CupertinoIcons.mic_fill), findsNothing);
    expect(find.byKey(const Key('v2-inspiration-send')), findsOneWidget);
    expect(find.byKey(const Key('v2-model-inspiration-strip')), findsNothing);
    expect(find.text('模型筛选'), findsNothing);
  });

  testWidgets('AI entry only shows model-selected creative candidates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentSnapshotProvider.overrideWith(
            _FixedEnvironmentController.new,
          ),
          companionInventoryProvider.overrideWith(
            _ModelSelectedInventoryController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: V2InspirationPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('v2-model-inspiration-strip')), findsOneWidget);
    expect(find.text('为你筛过的灵感'), findsOneWidget);
    expect(find.text('模型筛选'), findsOneWidget);
    expect(find.text('雨后倒影'), findsOneWidget);
    expect(find.text('低机位重复'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('v2-model-inspiration-strip')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('框中框'), findsOneWidget);
  });
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() async =>
      ContextFixtures.quietCity(observedAt: DateTime.now());
}

class _ModelSelectedInventoryController extends CompanionInventoryController {
  @override
  Future<List<CompanionInsight>> build() async => [
    _creativeInsight('reflection', '雨后倒影', '利用真实积水寻找城市灯光的倒影。'),
    _creativeInsight('repetition', '低机位重复', '寻找栏杆、台阶或路灯形成的重复节奏。'),
    _creativeInsight('frame', '框中框', '用门洞或树影组织画面层次。'),
  ];
}

CompanionInsight _creativeInsight(String id, String label, String body) {
  final now = DateTime.now().toUtc();
  return CompanionInsight(
    id: 'creative.$id',
    channel: InsightChannel.creativePrompt,
    title: label,
    body: body,
    shortLabel: label,
    emoji: '✨',
    generatedAt: now,
    startsAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    geoScope: ContextGeoScope.region,
    confidence: .8,
    priority: 60,
    action: ManifestAction.openCreativeDetail,
    sources: const [],
    canEnterBottle: true,
    canNotify: false,
  );
}
