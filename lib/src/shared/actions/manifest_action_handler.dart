import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/manifest/manifest_action_resolver.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> handleManifestAction(
  BuildContext context,
  ManifestItem item, {
  String? detailOverride,
}) async {
  final resolution = ManifestActionResolver.resolve(item);
  if (resolution.route case final route?) {
    context.go(route);
    return;
  }
  if (resolution.externalUri case final uri?) {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开权威来源，请稍后重试')));
    }
    return;
  }
  final panel = resolution.panel;
  if (panel == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这个动作已失效，请刷新情境后重试')));
    }
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(detailOverride ?? _detailFor(item.id, panel)),
          if (item.confidence case final confidence?) ...[
            const SizedBox(height: 12),
            Text('当前置信度 ${(confidence * 100).round()}%'),
          ],
        ],
      ),
    ),
  );
}

String _detailFor(String id, ManifestPanel panel) => switch (id) {
  'blue-hour' => '蓝调窗口已经接近，留意天空亮度与城市灯光的平衡。',
  'alpenglow' => '低角度光线条件成立，但山体是否受光仍取决于局部遮挡。',
  'dust-light' => '风沙与低角度光线可能形成层次，同时注意保护相机与呼吸安全。',
  'mist' => '雾气正在影响能见度，可观察前后景层次与光束方向。',
  'thunderstorm' => '雷暴属于稳定安全提醒。请远离制高点、水边、孤立树木和金属设备。',
  'strong-wind' => '当前风力较强，请固定三脚架并谨慎使用无人机。',
  'heavy-rain' => '当前降水较强，注意低洼地、沟谷、涉水路段和设备防水。',
  _ => switch (panel) {
    ManifestPanel.weather => '结合当前天气与能见度判断拍摄方式。',
    ManifestPanel.safety => '此信息属于稳定安全通道，请优先采取规避措施。',
  },
};
