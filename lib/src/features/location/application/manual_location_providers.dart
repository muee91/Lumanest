import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/features/location/domain/location_search_result.dart';

class ManualLocationSelection {
  const ManualLocationSelection({
    required this.name,
    required this.location,
    this.address,
  });

  final String name;
  final String? address;
  final LocationReading location;
}

class ManualLocationController extends Notifier<ManualLocationSelection?> {
  @override
  ManualLocationSelection? build() => null;

  void select(LocationSearchResult result) {
    state = ManualLocationSelection(
      name: result.name,
      address: result.address,
      location: LocationReading(
        point: ChinaCoordinateConverter.gcj02ToWgs84(result.point),
        recordedAt: DateTime.now().toUtc(),
        // Search results identify a place, not a GNSS point. Keep this
        // deliberately conservative for downstream presentation.
        accuracyMeters: 1000,
      ),
    );
  }

  void clear() => state = null;
}

final manualLocationProvider =
    NotifierProvider<ManualLocationController, ManualLocationSelection?>(
      ManualLocationController.new,
    );
