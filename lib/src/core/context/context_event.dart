enum ContextEventChannel {
  opportunity,
  safety,
  wildlifeOpportunity,
  wildlifeSafety,
}

enum ContextEventSource { weather, solar, rule, wildlifeHistorical, official }

class ContextEvent {
  const ContextEvent({
    required this.id,
    required this.channel,
    required this.source,
    required this.observedAt,
    required this.expiresAt,
    required this.confidence,
  }) : assert(confidence >= 0 && confidence <= 1);

  final String id;
  final ContextEventChannel channel;
  final ContextEventSource source;
  final DateTime observedAt;
  final DateTime expiresAt;
  final double confidence;

  bool isExpiredAt(DateTime moment) => !expiresAt.isAfter(moment);
}
