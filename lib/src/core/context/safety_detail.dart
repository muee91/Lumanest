class SafetyDetail {
  const SafetyDetail({
    required this.eventId,
    required this.title,
    required this.description,
    required this.guidance,
  });

  final String eventId;
  final String title;
  final String description;
  final List<String> guidance;
}

abstract interface class SafetyDetailRepository {
  Future<SafetyDetail?> fetch({
    required String contextId,
    required String eventId,
  });
}
