enum SceneType { city, lake, mountain, desert, village, driving, hiking }

enum DayPhase { dawn, day, sunset, blueHour, night }

enum WeatherType { clear, cloudy, rain, snow, dust }

class ContextSnapshot {
  ContextSnapshot({
    required this.id,
    required this.observedAt,
    required this.expiresAt,
    required this.primaryScene,
    required this.dayPhase,
    required this.weather,
    required this.activeRoute,
    List<String> opportunityIds = const [],
    List<String> safetyEventIds = const [],
    List<String> wildlifeEventIds = const [],
  }) : opportunityIds = List.unmodifiable(opportunityIds),
       safetyEventIds = List.unmodifiable(safetyEventIds),
       wildlifeEventIds = List.unmodifiable(wildlifeEventIds);

  final String id;
  final DateTime observedAt;
  final DateTime expiresAt;
  final SceneType primaryScene;
  final DayPhase dayPhase;
  final WeatherType weather;
  final bool activeRoute;
  final List<String> opportunityIds;
  final List<String> safetyEventIds;
  final List<String> wildlifeEventIds;
}
