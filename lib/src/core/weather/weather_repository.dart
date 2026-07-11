import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/weather/weather_observation.dart';

abstract interface class WeatherRepository {
  Future<WeatherObservation> fetchCurrent(GeoPoint point);
}
