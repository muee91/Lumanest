import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_now_mission_stage.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';

TripTask _task({TripTaskStage stage = TripTaskStage.planning}) => TripTask(
  id: 'trip_1',
  destinationName: '新都桥',
  destination: const GeoPoint(latitude: 30.04, longitude: 101.5),
  travelMode: TripTravelMode.driving,
  stage: stage,
  createdAt: DateTime.utc(2026, 11, 7),
);

class _RestoredTripStore implements TripTaskStore {
  _RestoredTripStore(this.task);
  TripTask? task;

  @override
  Future<TripTask?> read() async => task;

  @override
  Future<void> write(TripTask value) async {
    task = value;
  }

  @override
  Future<void> clear() async {
    task = null;
  }
}

Widget _stage(
  TripTask task, {
  VoidCallback? onStart,
  ValueChanged<bool>? onWatchChange,
  VoidCallback? onOpenShooting,
  String? safetyTitle,
  VoidCallback? onOpenSafety,
}) => MaterialApp(
  home: Scaffold(
    body: V2PageStage(
      child: V2NowMissionStage(
        task: task,
        onStart: onStart ?? () {},
        onEnterField: () {},
        onComplete: () {},
        onCancel: () {},
        onWatchChange: onWatchChange ?? (_) {},
        onOpenRoute: () {},
        onOpenEnvironment: () {},
        onOpenShooting: onOpenShooting ?? () {},
        safetyTitle: safetyTitle,
        onOpenSafety: onOpenSafety,
      ),
    ),
  ),
);

void main() {
  testWidgets('restored task appears before the automatic location gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripTaskStoreProvider.overrideWithValue(_RestoredTripStore(_task())),
        ],
        child: const MaterialApp(home: V2TodayPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('v2-now-mission-stage')), findsOneWidget);
    expect(find.text('新都桥'), findsOneWidget);
    expect(find.text('允许位置并继续'), findsNothing);
    expect(find.text('开始行程'), findsOneWidget);
  });

  testWidgets('watch opt-in requires confirmation and does not claim push', (
    tester,
  ) async {
    bool? requested;
    await tester.pumpWidget(
      _stage(_task(), onWatchChange: (enabled) => requested = enabled),
    );

    expect(find.text('未开启后台守候。'), findsOneWidget);
    await tester.ensureVisible(find.text('开启守候'));
    await tester.tap(find.text('开启守候'));
    await tester.pumpAndSettle();

    expect(find.text('请求云端守候？'), findsOneWidget);
    expect(find.textContaining('不提供远程推送'), findsOneWidget);
    expect(requested, isNull);

    await tester.tap(find.text('确认开启'));
    await tester.pumpAndSettle();

    expect(requested, isTrue);
  });

  testWidgets('field stage describes manual presence and opens evidence', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _stage(
        _task(stage: TripTaskStage.field),
        onOpenShooting: () => opened = true,
      ),
    );

    expect(find.text('已手动进入现场'), findsOneWidget);
    expect(find.textContaining('不代表 GPS 已核实到达'), findsOneWidget);
    await tester.ensureVisible(find.text('查看环境与光线'));
    await tester.tap(find.text('查看环境与光线'));
    expect(opened, isTrue);
  });

  testWidgets('existing blocking safety entry stays actionable', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _stage(
        _task(),
        safetyTitle: '道路临时封闭',
        onOpenSafety: () => opened = true,
      ),
    );

    await tester.tap(find.textContaining('道路临时封闭'));
    expect(opened, isTrue);
  });
}
