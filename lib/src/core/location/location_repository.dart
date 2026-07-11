import 'package:luma_nest/src/core/location/location_reading.dart';

abstract interface class LocationRepository {
  Future<LocationReading> current();
}
