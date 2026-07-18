import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/features/location/domain/manual_location_selection.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';
import 'package:luma_nest/src/features/location/infrastructure/manual_location_store.dart';

class ManualLocationController extends AsyncNotifier<ManualLocationSelection?> {
  @override
  Future<ManualLocationSelection?> build() =>
      ref.watch(manualLocationStoreProvider).read();

  Future<void> select(LocationSearchResult result) async {
    final selectedAt = DateTime.now().toUtc();
    final point = result.point.coordinateSystem == CoordinateSystem.gcj02
        ? ChinaCoordinateConverter.gcj02ToWgs84(result.point)
        : result.point;
    final value = ManualLocationSelection(
      name: result.name,
      address: result.address,
      selectedAt: selectedAt,
      location: LocationReading(
        point: point,
        recordedAt: selectedAt,
        // Search results identify a place, not a GNSS point. Keep this
        // deliberately conservative for downstream presentation.
        accuracyMeters: 1000,
      ),
    );
    await ref.read(manualLocationStoreProvider).write(value);
    state = AsyncData(value);
  }

  Future<void> clear() async {
    await ref.read(manualLocationStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final manualLocationProvider =
    AsyncNotifierProvider<ManualLocationController, ManualLocationSelection?>(
      ManualLocationController.new,
    );
