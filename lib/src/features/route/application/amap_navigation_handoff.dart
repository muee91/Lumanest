import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:url_launcher/url_launcher.dart';

/// Transfers only an already selected destination to AMap. Environment data,
/// route history and user preferences never leave the app through this path.
abstract interface class AmapNavigationHandoff {
  Future<bool> open({
    required String destinationName,
    required GeoPoint destination,
    required RouteTravelMode mode,
  });
}

class UrlLauncherAmapNavigationHandoff implements AmapNavigationHandoff {
  @override
  Future<bool> open({
    required String destinationName,
    required GeoPoint destination,
    required RouteTravelMode mode,
  }) async {
    final native = buildNativeUri(
      destinationName: destinationName,
      destination: destination,
      mode: mode,
    );
    if (await launchUrl(native, mode: LaunchMode.externalApplication)) {
      return true;
    }
    return launchUrl(
      buildWebUri(
        destinationName: destinationName,
        destination: destination,
        mode: mode,
      ),
      mode: LaunchMode.externalApplication,
    );
  }

  static Uri buildNativeUri({
    required String destinationName,
    required GeoPoint destination,
    required RouteTravelMode mode,
  }) {
    final point = ChinaCoordinateConverter.wgs84ToGcj02(destination);
    return Uri(
      scheme: 'androidamap',
      host: 'route',
      queryParameters: {
        'sourceApplication': 'LumaNest',
        'dlat': '${point.latitude}',
        'dlon': '${point.longitude}',
        'dname': destinationName,
        'dev': '0',
        't': mode == RouteTravelMode.walking ? '2' : '0',
      },
    );
  }

  static Uri buildWebUri({
    required String destinationName,
    required GeoPoint destination,
    required RouteTravelMode mode,
  }) {
    final point = ChinaCoordinateConverter.wgs84ToGcj02(destination);
    return Uri.https('uri.amap.com', '/navigation', {
      'to': '${point.longitude},${point.latitude},$destinationName',
      'mode': mode == RouteTravelMode.walking ? 'walk' : 'car',
      'coordinate': 'gaode',
      'callnative': '1',
    });
  }
}

final amapNavigationHandoffProvider = Provider<AmapNavigationHandoff>((ref) {
  return UrlLauncherAmapNavigationHandoff();
});
