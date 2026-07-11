import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/solar/solar_service.dart';
import 'package:nrel_spa/nrel_spa.dart';

class NrelSolarService implements SolarService {
  @override
  SolarState calculate({
    required GeoPoint point,
    required DateTime moment,
    required Duration utcOffset,
    double altitudeMeters = 0,
  }) {
    point.validate();
    final utcMoment = moment.toUtc();
    final result = getSpa(
      utcMoment,
      point.latitude,
      point.longitude,
      utcOffset.inMinutes / Duration.minutesPerHour,
      elevation: altitudeMeters,
    );
    final sunrise = _localFractionalHourToUtc(
      result.sunrise,
      utcMoment,
      utcOffset,
    );
    final sunset = _localFractionalHourToUtc(
      result.sunset,
      utcMoment,
      utcOffset,
    );
    final elevation = 90 - result.zenith;

    return SolarState(
      observedAt: utcMoment,
      elevationDegrees: elevation,
      azimuthDegrees: result.azimuth,
      sunrise: sunrise,
      sunset: sunset,
      dayPhase: _dayPhase(utcMoment, sunrise, sunset, elevation),
    );
  }

  DateTime? _localFractionalHourToUtc(
    double fractionalHour,
    DateTime utcMoment,
    Duration utcOffset,
  ) {
    if (!fractionalHour.isFinite || fractionalHour < 0) return null;

    final localDate = utcMoment.add(utcOffset);
    final localMidnightAsUtc = DateTime.utc(
      localDate.year,
      localDate.month,
      localDate.day,
    ).subtract(utcOffset);
    final microseconds = (fractionalHour * Duration.microsecondsPerHour)
        .round();
    return localMidnightAsUtc.add(Duration(microseconds: microseconds));
  }

  DayPhase _dayPhase(
    DateTime moment,
    DateTime? sunrise,
    DateTime? sunset,
    double elevation,
  ) {
    if (sunrise == null || sunset == null) {
      return elevation >= 0 ? DayPhase.day : DayPhase.night;
    }

    final dawnStart = sunrise.subtract(const Duration(hours: 1));
    final dawnEnd = sunrise.add(const Duration(minutes: 30));
    final sunsetStart = sunset.subtract(const Duration(hours: 1));
    final sunsetEnd = sunset.add(const Duration(minutes: 20));
    final blueHourEnd = sunset.add(const Duration(hours: 1));

    if (moment.isBefore(dawnStart)) return DayPhase.night;
    if (moment.isBefore(dawnEnd)) return DayPhase.dawn;
    if (moment.isBefore(sunsetStart)) return DayPhase.day;
    if (moment.isBefore(sunsetEnd)) return DayPhase.sunset;
    if (moment.isBefore(blueHourEnd)) return DayPhase.blueHour;
    return DayPhase.night;
  }
}
