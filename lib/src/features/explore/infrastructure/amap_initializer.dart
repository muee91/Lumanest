import 'package:amap_map/amap_map.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x_amap_base/x_amap_base.dart';

abstract class AmapInitializerGateway {
  void updatePrivacyAgree(AMapPrivacyStatement statement);

  void init(BuildContext context, {AMapApiKey? apiKey});
}

class DefaultAmapInitializerGateway implements AmapInitializerGateway {
  const DefaultAmapInitializerGateway();

  @override
  void updatePrivacyAgree(AMapPrivacyStatement statement) {
    AMapInitializer.updatePrivacyAgree(statement);
  }

  @override
  void init(BuildContext context, {AMapApiKey? apiKey}) {
    AMapInitializer.init(context, apiKey: apiKey);
  }
}

final amapInitializerGatewayProvider = Provider<AmapInitializerGateway>((ref) {
  return const DefaultAmapInitializerGateway();
});

typedef MapSurfaceBuilder = Widget Function();

final mapSurfaceBuilderProvider = Provider<MapSurfaceBuilder>((ref) {
  return () => const AMapWidget();
});
