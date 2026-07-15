import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer.dart';
import 'package:luma_nest/src/features/explore/domain/wildlife_map_layer_repository.dart';
import 'package:luma_nest/src/features/explore/infrastructure/data_broker_wildlife_map_layer_repository.dart';

final wildlifeMapLayerRepositoryProvider = Provider<WildlifeMapLayerRepository>(
  (ref) {
    final config = ref.watch(environmentConfigProvider);
    return DataBrokerWildlifeMapLayerRepository(
      brokerBaseUrl: config.dataBrokerBaseUrl,
      serviceToken: config.lumaNestServiceToken,
      transport: DioWildlifeMapLayerTransport(
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            sendTimeout: const Duration(seconds: 5),
          ),
        ),
      ),
    );
  },
);

typedef WildlifeMapLayerQuery = ({
  double latitude,
  double longitude,
  int radiusKilometers,
});

final wildlifeMapLayerProvider = FutureProvider.autoDispose
    .family<WildlifeMapLayer, WildlifeMapLayerQuery>((ref, query) {
      return ref
          .watch(wildlifeMapLayerRepositoryProvider)
          .fetch(
            center: GeoPoint(
              latitude: query.latitude,
              longitude: query.longitude,
            ),
            radiusKilometers: query.radiusKilometers,
          );
    });
