import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/manifest/manifest_action_resolver.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/core/photography/opportunity_catalog.dart';
import 'package:luma_nest/src/shared/widgets/manifest_event_metadata.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> handleManifestAction(
  BuildContext context,
  ManifestItem item, {
  String? detailOverride,
  List<String> guidance = const [],
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
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final metadata = manifestEventMetadata(item);
      return Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 4,
          bottom: MediaQuery.paddingOf(context).bottom + 34,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(detailOverride ?? _detailFor(item.id, panel)),
              if (guidance.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  '现在做什么',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final guidanceItem in guidance)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.check_circle_outline, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(guidanceItem)),
                      ],
                    ),
                  ),
              ],
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(metadata.join(' · ')),
              ],
              if (item.confidence case final confidence?) ...[
                const SizedBox(height: 8),
                Text('当前置信度 ${(confidence * 100).round()}%'),
              ],
            ],
          ),
        ),
      );
    },
  );
}

String _detailFor(String id, ManifestPanel panel) {
  final definition = OpportunityCatalog.current.byId[id];
  if (panel == ManifestPanel.creative && definition?.isActiveCore == true) {
    return definition!.presentation.fallbackSummary ?? '结合当前证据与现场条件判断拍摄方式。';
  }
  return switch (id) {
    'thunderstorm' => '雷暴属于稳定安全提醒。请远离制高点、水边、孤立树木和金属设备。',
    'strong-wind' => '当前风力较强，请固定三脚架并谨慎使用无人机。',
    'heavy-rain' => '当前降水较强，注意低洼地、沟谷、涉水路段和设备防水。',
    _ =>
      panel == ManifestPanel.safety
          ? '此信息属于稳定安全通道，请优先采取规避措施。'
          : '结合当前证据与现场条件判断拍摄方式。',
  };
}
