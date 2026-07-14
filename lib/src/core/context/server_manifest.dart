/// Layout modes the server may express in its manifest.
///
/// Unlike [LayoutMode] in the UI layer, this enum mirrors the server contract
/// verbatim — `quiet`, `opportunity`, `safety` — so that the client can honour
/// the server's intent without collapsing unknown values silently.
enum ServerManifestLayout {
  quiet,
  opportunity,
  safety;

  static ServerManifestLayout? fromServerString(String? value) {
    return switch (value) {
      'quiet' => ServerManifestLayout.quiet,
      'opportunity' => ServerManifestLayout.opportunity,
      'safety' => ServerManifestLayout.safety,
      _ => null,
    };
  }
}

/// Structured server-side manifest carried inside a [ContextSnapshot].
///
/// This domain object is intentionally UI-agnostic. It records the server's
/// layout decision and the event IDs it references. The [ManifestPolicy] layer
/// is responsible for translating it into a [UiManifest].
///
/// Validation runs at construction time:
/// - `secondaryEventIds` may have at most 2 entries
/// - All event IDs must be non-empty
/// - All lists must be duplicate-free
/// - `primaryEventId` must not appear in `secondaryEventIds`
class ServerManifest {
  ServerManifest({
    required this.layout,
    this.primaryEventId,
    List<String> secondaryEventIds = const [],
    List<String> safetyEventIds = const [],
  }) : secondaryEventIds = List.unmodifiable(secondaryEventIds),
       safetyEventIds = List.unmodifiable(safetyEventIds) {
    ArgumentError.checkNotNull(layout, 'layout');
    if (primaryEventId != null && primaryEventId!.isEmpty) {
      throw ArgumentError('primaryEventId must not be empty');
    }
    if (this.secondaryEventIds.length > 2) {
      throw ArgumentError(
        'secondaryEventIds must have at most 2 items, '
        'got ${this.secondaryEventIds.length}',
      );
    }
    _requireNonEmpty(this.secondaryEventIds, 'secondaryEventIds');
    _requireNonEmpty(this.safetyEventIds, 'safetyEventIds');
    _requireNoDuplicates(this.secondaryEventIds, 'secondaryEventIds');
    _requireNoDuplicates(this.safetyEventIds, 'safetyEventIds');
    if (primaryEventId != null &&
        this.secondaryEventIds.contains(primaryEventId)) {
      throw ArgumentError(
        'primaryEventId must not appear in secondaryEventIds',
      );
    }
  }

  final ServerManifestLayout layout;
  final String? primaryEventId;
  final List<String> secondaryEventIds;
  final List<String> safetyEventIds;

  ServerManifest copyWith({
    ServerManifestLayout? layout,
    String? Function()? primaryEventId,
    List<String>? secondaryEventIds,
    List<String>? safetyEventIds,
  }) {
    return ServerManifest(
      layout: layout ?? this.layout,
      primaryEventId: primaryEventId != null
          ? primaryEventId()
          : this.primaryEventId,
      secondaryEventIds:
          secondaryEventIds ?? this.secondaryEventIds.toList(growable: false),
      safetyEventIds:
          safetyEventIds ?? this.safetyEventIds.toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerManifest &&
          layout == other.layout &&
          primaryEventId == other.primaryEventId &&
          _listEquals(secondaryEventIds, other.secondaryEventIds) &&
          _listEquals(safetyEventIds, other.safetyEventIds);

  @override
  int get hashCode => Object.hash(
    layout,
    primaryEventId,
    Object.hashAll(secondaryEventIds),
    Object.hashAll(safetyEventIds),
  );

  static void _requireNonEmpty(List<String> ids, String name) {
    for (final id in ids) {
      if (id.isEmpty) {
        throw ArgumentError('$name must not contain empty strings');
      }
    }
  }

  static void _requireNoDuplicates(List<String> ids, String name) {
    if (ids.toSet().length != ids.length) {
      throw ArgumentError('$name must not contain duplicates');
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
