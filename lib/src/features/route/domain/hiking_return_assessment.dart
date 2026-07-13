import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';

enum HikingReturnRisk { beforeSunset, afterSunset, unknown }

class HikingReturnAssessment {
  const HikingReturnAssessment({
    required this.outboundArrival,
    required this.estimatedReturnArrival,
    required this.risk,
    this.latestReturnDeparture,
  });

  final DateTime outboundArrival;
  final DateTime estimatedReturnArrival;
  final HikingReturnRisk risk;
  final DateTime? latestReturnDeparture;

  static HikingReturnAssessment? build({
    required DrivingRoute route,
    required ContextSnapshot snapshot,
    required DateTime departureAt,
  }) {
    if (route.travelMode != RouteTravelMode.walking) return null;
    final departure = departureAt.toUtc();
    final leg = Duration(seconds: route.durationSeconds);
    final outboundArrival = departure.add(leg);
    final returnArrival = outboundArrival.add(leg);
    final sunset = snapshot.sunset?.toUtc();
    if (sunset == null) {
      return HikingReturnAssessment(
        outboundArrival: outboundArrival,
        estimatedReturnArrival: returnArrival,
        risk: HikingReturnRisk.unknown,
      );
    }
    return HikingReturnAssessment(
      outboundArrival: outboundArrival,
      estimatedReturnArrival: returnArrival,
      latestReturnDeparture: sunset.subtract(leg),
      risk: returnArrival.isAfter(sunset)
          ? HikingReturnRisk.afterSunset
          : HikingReturnRisk.beforeSunset,
    );
  }
}
