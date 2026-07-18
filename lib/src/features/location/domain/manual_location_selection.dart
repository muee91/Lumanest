import 'package:luma_nest/src/core/location/location_reading.dart';

class ManualLocationSelection {
  const ManualLocationSelection({
    required this.name,
    required this.location,
    required this.selectedAt,
    this.address,
  });

  final String name;
  final String? address;
  final LocationReading location;
  final DateTime selectedAt;
}
