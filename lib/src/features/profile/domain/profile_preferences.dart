/// Immutable accessibility and ambient preferences for the profile screen.
///
/// Phase 1 keeps these in-memory only; persistence is deferred to a later
/// Drift-backed phase. Instances are immutable and toggles return new copies.
class ProfilePreferences {
  const ProfilePreferences({
    this.ambientBackgroundEnabled = true,
    this.reduceMotion = false,
    this.reduceFlashing = false,
  });

  /// Whether the ambient environment background should animate behind the UI.
  final bool ambientBackgroundEnabled;

  /// Whether low-motion rendering is requested.
  final bool reduceMotion;

  /// Whether flashing/animated content should be dampened.
  final bool reduceFlashing;

  ProfilePreferences copyWith({
    bool? ambientBackgroundEnabled,
    bool? reduceMotion,
    bool? reduceFlashing,
  }) {
    return ProfilePreferences(
      ambientBackgroundEnabled:
          ambientBackgroundEnabled ?? this.ambientBackgroundEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      reduceFlashing: reduceFlashing ?? this.reduceFlashing,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProfilePreferences &&
        other.ambientBackgroundEnabled == ambientBackgroundEnabled &&
        other.reduceMotion == reduceMotion &&
        other.reduceFlashing == reduceFlashing;
  }

  @override
  int get hashCode =>
      Object.hash(ambientBackgroundEnabled, reduceMotion, reduceFlashing);
}
