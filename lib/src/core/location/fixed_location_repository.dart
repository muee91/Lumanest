import 'package:luma_nest/src/core/location/location_reading.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';

class FixedLocationRepository implements LocationRepository {
  const FixedLocationRepository(this.reading);

  final LocationReading reading;

  @override
  Future<LocationReading> current() async => reading;
}
