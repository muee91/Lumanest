enum ContextEventChannel {
  opportunity,
  safety,
  wildlifeOpportunity,
  wildlifeSafety,
}

enum ContextEventSource {
  weather,
  solar,
  rule,
  wildlifeHistorical,
  official,
  astronomyCatalog,
}

enum ContextGeoScope { point, regional, route }

enum ContextSafetyLevel { info, caution, warning, critical }

enum ContextAction {
  openExplore,
  openShootingWindow,
  openWeather,
  openSafety,
  openRoute,
  openAuthority,
}

class ContextEvent {
  const ContextEvent({
    required this.id,
    required this.channel,
    required this.source,
    required this.observedAt,
    required this.expiresAt,
    required this.confidence,
    this.geoScope,
    this.safetyLevel,
    this.allowedAction,
    this.title,
    this.sourceUri,
  }) : assert(confidence >= 0 && confidence <= 1);

  final String id;
  final ContextEventChannel channel;
  final ContextEventSource source;
  final DateTime observedAt;
  final DateTime expiresAt;
  final double confidence;
  final ContextGeoScope? geoScope;
  final ContextSafetyLevel? safetyLevel;
  final ContextAction? allowedAction;
  final String? title;
  final Uri? sourceUri;

  bool isExpiredAt(DateTime moment) => !expiresAt.isAfter(moment);
}
