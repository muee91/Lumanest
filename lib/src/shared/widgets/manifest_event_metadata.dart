import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';

List<String> manifestEventMetadata(ManifestItem item) => [
  if (item.source case final source?) _sourceLabel(source),
  if (item.safetyLevel case final level?) _safetyLevelLabel(level),
  if (item.geoScope case final scope?) _geoScopeLabel(scope),
  if (item.observedAt case final observedAt?) '${_dateTimeLabel(observedAt)}更新',
  if (item.expiresAt case final expiresAt?) '${_dateTimeLabel(expiresAt)}前有效',
];

String _sourceLabel(ContextEventSource source) => switch (source) {
  ContextEventSource.weather => '天气数据',
  ContextEventSource.solar => '本地日月计算',
  ContextEventSource.rule => '情境安全规则',
  ContextEventSource.wildlifeHistorical => '许可历史记录',
  ContextEventSource.official => '官方来源',
  ContextEventSource.astronomyCatalog => '权威天象目录',
};

String _safetyLevelLabel(ContextSafetyLevel level) => switch (level) {
  ContextSafetyLevel.info => '提示',
  ContextSafetyLevel.caution => '留意',
  ContextSafetyLevel.warning => '警告',
  ContextSafetyLevel.critical => '严重',
};

String _geoScopeLabel(ContextGeoScope scope) => switch (scope) {
  ContextGeoScope.point => '当前地点',
  ContextGeoScope.region => '附近区域',
  ContextGeoScope.route => '当前路线',
};

String _dateTimeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}月${local.day}日 $hour:$minute';
}
