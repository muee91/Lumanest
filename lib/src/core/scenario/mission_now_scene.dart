import 'package:luma_nest/src/core/mission/mission_repository.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';

/// A read-only projection of the persisted trip intent into the four 2.0
/// surfaces. It must never infer forecast, ETA, arrival or push delivery from
/// a local stage transition.
enum MissionNowMode { quiet, watching, traveling, onSite }

/// Local opt-in and remote acknowledgement are deliberately different facts.
enum MissionWatchStatus { disabled, awaitingEnable, acknowledged, awaitingDisable }

class MissionNowScene {
  const MissionNowScene({
    required this.mode,
    required this.watchStatus,
    this.task,
  });

  final MissionNowMode mode;
  final MissionWatchStatus watchStatus;
  final TripTask? task;

  bool get hasActiveTask => task != null;

  String get modeLabel => switch (mode) {
    MissionNowMode.quiet => '规划中',
    MissionNowMode.watching => '目标守候',
    MissionNowMode.traveling => '在路上',
    MissionNowMode.onSite => '现场',
  };

  String get headline => switch (mode) {
    MissionNowMode.quiet => hasActiveTask ? '已记下这次出行' : '没有正在进行的任务',
    MissionNowMode.watching => watchStatus == MissionWatchStatus.acknowledged
        ? '正在关注这次拍摄'
        : '正在申请目标守候',
    MissionNowMode.traveling => '这次行程已开始',
    MissionNowMode.onSite => '已手动进入现场',
  };

  String get description => switch (mode) {
    MissionNowMode.quiet => '目标已保存在设备上。可以先探路，也可以明确请求云端守候。',
    MissionNowMode.watching => '仅关注你主动授权的目标。窗口、出发时间和天气须以最新来源核实。',
    MissionNowMode.traveling => '查看真实路线与沿线变化；不会自动开启导航或后台位置追踪。',
    MissionNowMode.onSite => '这是手动标记的行程状态，不代表 GPS 已核实到达，也不是相机取景器。',
  };

  String get watchDescription => switch (watchStatus) {
    MissionWatchStatus.disabled => '未开启后台守候。',
    MissionWatchStatus.awaitingEnable =>
      '守候请求尚未得到服务端确认；不能依赖后台检查或远程提醒。',
    MissionWatchStatus.acknowledged =>
      '上次同步显示云端检查已启用；这不是实时在线证明，远程推送尚未接入。',
    MissionWatchStatus.awaitingDisable =>
      '已在本机停止守候，但服务端停止状态待确认；网络恢复后仍需核对。',
  };

  bool get stageSyncPending {
    final current = task;
    if (current == null || current.remoteMissionId == null) return false;
    if (current.pendingTransition != null) return true;
    final remote = current.remoteMissionStage;
    if (remote == null) return true;
    return remote.name != current.stage.name;
  }

  static MissionNowScene fromTask(TripTask? task) {
    if (task == null || !task.isOpen) {
      return const MissionNowScene(
        mode: MissionNowMode.quiet,
        watchStatus: MissionWatchStatus.disabled,
      );
    }
    final watchStatus = switch (task.watchEnabled) {
      false when task.remoteMissionWatchEnabled == true ||
          task.pendingWatchEnabled == false =>
        MissionWatchStatus.awaitingDisable,
      false => MissionWatchStatus.disabled,
      true when task.remoteMissionId != null &&
          task.remoteMissionWatchEnabled == true &&
          task.pendingWatchEnabled == null &&
          !task.remoteCreationPending &&
          task.remoteMissionStage != MissionRemoteStage.cancelled &&
          task.remoteMissionStage != MissionRemoteStage.completed =>
        MissionWatchStatus.acknowledged,
      true => MissionWatchStatus.awaitingEnable,
    };
    final mode = switch (task.stage) {
      TripTaskStage.planning => task.watchEnabled
          ? MissionNowMode.watching
          : MissionNowMode.quiet,
      TripTaskStage.enRoute => MissionNowMode.traveling,
      TripTaskStage.field => MissionNowMode.onSite,
      TripTaskStage.completed || TripTaskStage.cancelled => MissionNowMode.quiet,
    };
    return MissionNowScene(mode: mode, watchStatus: watchStatus, task: task);
  }
}
