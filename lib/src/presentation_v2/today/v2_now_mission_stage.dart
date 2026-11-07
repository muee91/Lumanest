import 'package:flutter/material.dart';
import 'package:luma_nest/src/core/scenario/mission_now_scene.dart';
import 'package:luma_nest/src/core/trip/trip_task.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

/// Task-first Today surface. All facts shown here come from the durable local
/// TripTask projection; it does not invent a window or silently request GPS.
class V2NowMissionStage extends StatelessWidget {
  const V2NowMissionStage({
    super.key,
    required this.task,
    required this.onStart,
    required this.onEnterField,
    required this.onComplete,
    required this.onCancel,
    required this.onWatchChange,
    required this.onOpenRoute,
    required this.onOpenEnvironment,
    required this.onOpenShooting,
    this.safetyTitle,
    this.onOpenSafety,
  });

  final TripTask task;
  final VoidCallback onStart;
  final VoidCallback onEnterField;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final ValueChanged<bool> onWatchChange;
  final VoidCallback onOpenRoute;
  final VoidCallback onOpenEnvironment;
  final VoidCallback onOpenShooting;
  final String? safetyTitle;
  final VoidCallback? onOpenSafety;

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String detail,
    required String actionLabel,
    required VoidCallback action,
  }) async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (allowed == true && context.mounted) action();
  }

  @override
  Widget build(BuildContext context) {
    final scene = MissionNowScene.fromTask(task);
    final status = scene.watchDescription;
    final planning = task.stage == TripTaskStage.planning;
    final traveling = task.stage == TripTaskStage.enRoute;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const Key('v2-now-mission-stage'),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const V2BrandLockup(),
              const SizedBox(height: 26),
              Text(
                '此刻 · ${scene.modeLabel}',
                style: TextStyle(
                  color: context.v2Moss,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                scene.headline,
                key: const Key('v2-now-mission-verdict'),
                style: TextStyle(
                  color: context.v2Ink,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.14,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                task.destinationName,
                key: const Key('v2-now-mission-destination'),
                style: TextStyle(
                  color: context.v2Ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                scene.description,
                style: TextStyle(
                  color: context.v2MutedInk,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (safetyTitle != null && onOpenSafety != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onOpenSafety,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text(
                    '当前环境提醒 · $safetyTitle',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.v2Paper,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '守候与同步状态',
                        style: TextStyle(
                          color: context.v2Moss,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        status,
                        key: const Key('v2-now-mission-watch-status'),
                        style: TextStyle(
                          color: context.v2Ink,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      if (scene.stageSyncPending) ...[
                        const SizedBox(height: 8),
                        Text(
                          '本机行程阶段尚未与服务器核对一致。',
                          style: TextStyle(
                            color: context.v2MutedInk,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        '本页不推断拍摄成功率、实时 ETA 或已验证到场。',
                        style: TextStyle(
                          color: context.v2MutedInk,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: FilledButton(
                  key: const Key('v2-now-mission-primary'),
                  onPressed: planning
                      ? onStart
                      : traveling
                      ? onOpenRoute
                      : onOpenShooting,
                  child: Text(
                    planning
                        ? '开始行程'
                        : traveling
                        ? '查看真实路线'
                        : task.sessionId != null
                        ? '查看拍摄详情'
                        : '查看环境与光线',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.start,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (planning)
                    OutlinedButton(
                      onPressed: onOpenRoute,
                      child: const Text('先查看路线'),
                    ),
                  if (task.watchEnabled)
                    OutlinedButton(
                      onPressed: () => onWatchChange(false),
                      child: const Text('停止守候'),
                    )
                  else if (planning || traveling)
                    OutlinedButton(
                      onPressed: () => _confirm(
                        context,
                        title: '请求云端守候？',
                        detail:
                            '仅为这次明确目标启动后台检查。需要网络与服务端确认；目前不提供远程推送或必达保证。',
                        actionLabel: '确认开启',
                        action: () => onWatchChange(true),
                      ),
                      child: const Text('开启守候'),
                    ),
                  if (traveling)
                    OutlinedButton(
                      onPressed: onEnterField,
                      child: const Text('我已到现场（手动）'),
                    ),
                  if (task.stage == TripTaskStage.field) ...[
                    OutlinedButton(
                      onPressed: onOpenRoute,
                      child: const Text('回看路线'),
                    ),
                    OutlinedButton(
                      onPressed: () => _confirm(
                        context,
                        title: '结束本次行程？',
                        detail: '本次任务将标记为完成。云端状态可能需要联网同步。',
                        actionLabel: '确认完成',
                        action: onComplete,
                      ),
                      child: const Text('结束本次行程'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: onOpenEnvironment,
                    child: const Text('天气与光线依据'),
                  ),
                  TextButton(
                    onPressed: () => _confirm(
                      context,
                      title: '取消这次任务？',
                      detail: '任务会从当前主舞台退出；如果此前请求云端守候，撤销仍可能需要联网同步。',
                      actionLabel: '确认取消',
                      action: onCancel,
                    ),
                    child: const Text('取消任务'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '天气、天文与道路事实须在详情页查看新鲜度和来源；这里只显示任务状态，不以模型文字代替实时证据。',
                style: TextStyle(
                  color: context.v2MutedInk,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
