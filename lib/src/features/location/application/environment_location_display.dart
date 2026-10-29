import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
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

/// A single shared client for the place-name lookup. Building a `Dio` per
/// evaluation created a connection pool that was never closed; a provider-owned
/// client is disposed with the container.
final _locationDisplayDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

/// Resolves the device coordinate to the smallest useful administrative name.
/// The fallback remains terse and never appends source explanations to the
/// Today header.
final environmentLocationDisplayForSnapshotProvider =
    FutureProvider.autoDispose
        .family<EnvironmentLocationDisplay, ContextSnapshot>((ref, snapshot) async {
          final base = ref.read(environmentLocationDisplayProvider);
          if (base.source != EnvironmentLocationSource.device ||
              snapshot.location == null) {
            return base;
          }
          final config = ref.read(environmentConfigProvider);
          if (!config.isDataBrokerConfigured) return base;
          // The request must stop when the provider is disposed: a snapshot
          // refresh would otherwise leave a lookup running against a client that
          // is already closed.
          final cancelToken = CancelToken();
          ref.onDispose(() => cancelToken.cancel());
          try {
            final point = ChinaCoordinateConverter.wgs84ToGcj02(snapshot.location!);
            final response = await ref
                .read(_locationDisplayDioProvider)
                .get<Object?>(
                  '${config.dataBrokerBaseUrl}/v1/amap/scene-evidence',
                  queryParameters: {
                    'location': '${point.longitude},${point.latitude}',
                  },
                  options: Options(
                    headers: {
                      'Authorization': 'Bearer ${config.lumaNestServiceToken}',
                    },
                  ),
                  cancelToken: cancelToken,
                );
            final body = response.data;
            if (body is! Map || body['regeocode'] is! Map) return base;
            final component = (body['regeocode'] as Map)['addressComponent'];
            if (component is! Map) return base;
            final district = _text(component['district']);
            final city = _text(component['city']);
            final province = _text(component['province']);
            final label = district ?? city ?? province;
            return label == null
                ? base
                : EnvironmentLocationDisplay(label: label, source: base.source);
          } on Object {
            return base;
          }
        });

String? _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is List && value.length == 1) return _text(value.single);
  return null;
}
