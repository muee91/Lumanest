import 'package:luma_nest/src/core/weather/seven_timer_forecast.dart';

abstract interface class SevenTimerRepository {
  Future<SevenTimerForecast?> fetch({
    required double latitude,
    required double longitude,
    required SevenTimerProduct product,
  });
}
