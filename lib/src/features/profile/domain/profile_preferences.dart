enum AmbientMotionMode { full, energySaver, staticColor }

/// Immutable accessibility and ambient preferences for the profile screen.
///
/// Instances are immutable and persisted by the profile preferences store.
class ProfilePreferences {
  const ProfilePreferences({
    this.ambientBackgroundEnabled = true,
    this.reduceMotion = false,
    this.reduceFlashing = false,
    this.highContrast = false,
    this.ambientMotionMode = AmbientMotionMode.full,
  });

  /// Whether the ambient environment background should animate behind the UI.
  final bool ambientBackgroundEnabled;

  /// Whether low-motion rendering is requested.
  final bool reduceMotion;

  /// Whether flashing/animated content should be dampened.
  final bool reduceFlashing;

  /// Whether the app should use its maximum-contrast color scheme.
  final bool highContrast;
  final AmbientMotionMode ambientMotionMode;

  ProfilePreferences copyWith({
    bool? ambientBackgroundEnabled,
    bool? reduceMotion,
    bool? reduceFlashing,
    bool? highContrast,
    AmbientMotionMode? ambientMotionMode,
  }) {
    return ProfilePreferences(
      ambientBackgroundEnabled:
          ambientBackgroundEnabled ?? this.ambientBackgroundEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      reduceFlashing: reduceFlashing ?? this.reduceFlashing,
      highContrast: highContrast ?? this.highContrast,
      ambientMotionMode: ambientMotionMode ?? this.ambientMotionMode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProfilePreferences &&
        other.ambientBackgroundEnabled == ambientBackgroundEnabled &&
        other.reduceMotion == reduceMotion &&
        other.reduceFlashing == reduceFlashing &&
        other.highContrast == highContrast &&
        other.ambientMotionMode == ambientMotionMode;
  }

  @override
  int get hashCode => Object.hash(
    ambientBackgroundEnabled,
    reduceMotion,
    reduceFlashing,
    highContrast,
    ambientMotionMode,
  );
}
