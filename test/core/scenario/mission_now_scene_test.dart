import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';
import 'package:luma_nest/src/core/scenario/mission_now_scene.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';

TripTask _task({
  TripTaskStage stage = TripTaskStage.planning,
  bool watchEnabled = false,
  String? remoteId,
  bool? remoteWatchEnabled,
  bool? pendingWatchEnabled,
  MissionRemoteStage? remoteStage,
  String? pendingTransition,
  DateTime? remoteEndsAt,
}) => TripTask(
  id: 'trip_1',
  destinationName: '贡嘎山',
  destination: const GeoPoint(
    latitude: 29.6,
    longitude: 101.9,
    coordinateSystem: CoordinateSystem.wgs84,
  ),
  travelMode: TripTravelMode.driving,
  stage: stage,
  createdAt: DateTime.utc(2026, 11, 7),
  watchEnabled: watchEnabled,
  remoteMissionId: remoteId,
  remoteMissionWatchEnabled: remoteWatchEnabled,
  remoteMissionStage: remoteStage,
  remoteMissionEndsAt: remoteEndsAt,
  pendingWatchEnabled: pendingWatchEnabled,
  pendingTransition: pendingTransition,
);

void main() {
  test('no task is quiet and cannot be called a remote watch', () {
    final scene = MissionNowScene.fromTask(null);

    expect(scene.mode, MissionNowMode.quiet);
    expect(scene.hasActiveTask, false);
    expect(scene.watchStatus, MissionWatchStatus.disabled);
  });

  test('planning a destination does not authorize background checks', () {
    final scene = MissionNowScene.fromTask(_task());

    expect(scene.hasActiveTask, true);
    expect(scene.mode, MissionNowMode.quiet);
    expect(scene.watchStatus, MissionWatchStatus.disabled);
  });

  test('local watch intent is not mistaken for server acknowledgement', () {
    final scene = MissionNowScene.fromTask(_task(watchEnabled: true));

    expect(scene.mode, MissionNowMode.watching);
    expect(scene.watchStatus, MissionWatchStatus.awaitingEnable);
    expect(scene.watchDescription, contains('尚未得到服务端确认'));
  });

  test('acknowledged check remains distinct from remote push delivery', () {
    final scene = MissionNowScene.fromTask(
      _task(
        watchEnabled: true,
        remoteId: 'mis_123',
        remoteWatchEnabled: true,
        remoteStage: MissionRemoteStage.planning,
      ),
    );

    expect(scene.watchStatus, MissionWatchStatus.acknowledged);
    expect(scene.watchDescription, contains('远程推送尚未接入'));
  });

  test('acknowledged watch exposes the server expiry', () {
    final scene = MissionNowScene.fromTask(
      _task(
        watchEnabled: true,
        remoteId: 'mis_123',
        remoteWatchEnabled: true,
        remoteStage: MissionRemoteStage.planning,
        remoteEndsAt: DateTime.utc(2026, 11, 8),
      ),
    );

    expect(scene.watchDescription, contains('有效至'));
  });

  test('local stop cannot claim the server has stopped checking', () {
    final scene = MissionNowScene.fromTask(
      _task(
        remoteId: 'mis_123',
        remoteWatchEnabled: true,
        pendingWatchEnabled: false,
      ),
    );

    expect(scene.watchStatus, MissionWatchStatus.awaitingDisable);
    expect(scene.watchDescription, contains('服务端停止状态待确认'));
  });

  test('manual en-route and field states are not GPS arrival evidence', () {
    final traveling = MissionNowScene.fromTask(
      _task(
        stage: TripTaskStage.enRoute,
        remoteId: 'mis_123',
        remoteStage: MissionRemoteStage.planning,
        pendingTransition: 'start',
      ),
    );
    final field = MissionNowScene.fromTask(
      _task(stage: TripTaskStage.field),
    );

    expect(traveling.mode, MissionNowMode.traveling);
    expect(traveling.stageSyncPending, true);
    expect(field.mode, MissionNowMode.onSite);
    expect(field.description, contains('不代表 GPS 已核实到达'));
  });

  test('completed and cancelled tasks never occupy the Now stage', () {
    for (final stage in [TripTaskStage.completed, TripTaskStage.cancelled]) {
      final scene = MissionNowScene.fromTask(_task(stage: stage));

      expect(scene.hasActiveTask, false);
      expect(scene.mode, MissionNowMode.quiet);
    }
  });
}
