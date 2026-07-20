class EntryProvenance {
  const EntryProvenance({
    required this.sourceId,
    required this.observedAt,
    this.sourceUri,
  });

  final String sourceId;
  final DateTime observedAt;
  final Uri? sourceUri;
}
