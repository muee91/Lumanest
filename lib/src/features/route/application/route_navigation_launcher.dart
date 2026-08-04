import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/features/route/application/driving_route_providers.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:url_launcher/url_launcher.dart';

class RouteNavigationLauncher {
  const RouteNavigationLauncher._();

  static Future<bool> open(RouteDestination destination) async {
    final point = ChinaCoordinateConverter.wgs84ToGcj02(destination.point);
    final type = destination.travelMode == RouteTravelMode.walking ? 2 : 0;
    final native = Uri(
      scheme: 'amapuri',
      host: 'route',
      path: '/plan/',
      queryParameters: {
        'sourceApplication': '栖光',
        'dlat': point.latitude.toStringAsFixed(6),
        'dlon': point.longitude.toStringAsFixed(6),
        'dname': destination.name,
        'dev': '0',
        't': '$type',
      },
    );
    if (await canLaunchUrl(native)) {
      return launchUrl(native, mode: LaunchMode.externalApplication);
    }

    final webMode = destination.travelMode == RouteTravelMode.walking
        ? 'walk'
        : 'car';
    final fallback = Uri.https('uri.amap.com', '/navigation', {
      'to':
          '${point.longitude.toStringAsFixed(6)},'
          '${point.latitude.toStringAsFixed(6)},${destination.name}',
      'mode': webMode,
      'policy': '1',
      'src': 'lumanest',
      'coordinate': 'gaode',
      'callnative': '1',
    });
    return launchUrl(fallback, mode: LaunchMode.externalApplication);
  }
}
