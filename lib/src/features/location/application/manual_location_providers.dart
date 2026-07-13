import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

class ManualLocationController extends Notifier<LocationReading?> {
  @override
  LocationReading? build() => null;

  void select(LocationSearchResult result) {
    state = LocationReading(
      point: ChinaCoordinateConverter.gcj02ToWgs84(result.point),
      recordedAt: DateTime.now().toUtc(),
      // Search results identify a place, not a GNSS point. Keep this
      // deliberately conservative for downstream presentation.
      accuracyMeters: 1000,
    );
  }

  void clear() => state = null;
}

final manualLocationProvider =
    NotifierProvider<ManualLocationController, LocationReading?>(
      ManualLocationController.new,
    );
