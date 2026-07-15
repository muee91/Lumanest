import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/features/location/domain/base_region.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/base_region_store.dart';

class BaseRegionController extends AsyncNotifier<BaseRegion?> {
  @override
  Future<BaseRegion?> build() => ref.watch(baseRegionStoreProvider).read();

  Future<void> select(LocationSearchResult result) async {
    final now = DateTime.now().toUtc();
    final value = BaseRegion(
      name: result.name,
      address: result.address,
      location: LocationReading(
        point: ChinaCoordinateConverter.gcj02ToWgs84(result.point),
        recordedAt: now,
        accuracyMeters: 1000,
      ),
      selectedAt: now,
    );
    await ref.read(baseRegionStoreProvider).write(value);
    state = AsyncData(value);
  }

  Future<void> clear() async {
    await ref.read(baseRegionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final baseRegionProvider =
    AsyncNotifierProvider<BaseRegionController, BaseRegion?>(
      BaseRegionController.new,
    );
