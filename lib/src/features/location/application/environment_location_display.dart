import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/features/location/application/base_region_controller.dart';
import 'package:luma_nest/src/features/location/application/manual_location_providers.dart';

enum EnvironmentLocationSource { device, manual, baseRegion }

class EnvironmentLocationDisplay {
  const EnvironmentLocationDisplay({required this.label, required this.source});

  const EnvironmentLocationDisplay.device()
    : label = '当前位置',
      source = EnvironmentLocationSource.device;

  final String label;
  final EnvironmentLocationSource source;

  bool get isReference => source != EnvironmentLocationSource.device;

  String get sourceLabel => switch (source) {
    EnvironmentLocationSource.device => '当前位置',
    EnvironmentLocationSource.manual => '手动地点 · 非实时',
    EnvironmentLocationSource.baseRegion => '常驻地区 · 非实时',
  };

  /// The Today header is intentionally terse: source is conveyed by its icon
  /// and action, while the visible line stays a single place name.
  String get description => label;
}

final environmentLocationDisplayProvider = Provider<EnvironmentLocationDisplay>(
  (ref) {
    final manual = ref.watch(manualLocationProvider).asData?.value;
    if (manual != null) {
      return EnvironmentLocationDisplay(
        label: manual.name,
        source: EnvironmentLocationSource.manual,
      );
    }
    final baseRegion = ref.watch(baseRegionProvider).asData?.value;
    if (baseRegion != null) {
      return EnvironmentLocationDisplay(
        label: baseRegion.name,
        source: EnvironmentLocationSource.baseRegion,
      );
    }
    return const EnvironmentLocationDisplay.device();
  },
);
