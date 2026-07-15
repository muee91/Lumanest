enum AmbientMotionMode { full, energySaver, staticColor }

enum AiTone {
  concise('简洁'),
  balanced('均衡'),
  detailed('详细');

  const AiTone(this.label);
  final String label;
}

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
    this.photographyPreferences = const <String>{},
    this.activityPreferences = const <String>{},
    this.equipmentList = '',
    this.aiTone = AiTone.balanced,
    this.recommendationIntensity = 0.5,
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

  /// Selected photography genres (风光, 人文, 星空, 城市 …).
  final Set<String> photographyPreferences;

  /// Preferred activity types (自驾, 轻徒步, 重装徒步, 小众探索).
  final Set<String> activityPreferences;

  /// Free-form equipment description (camera, lenses, tripod …).
  final String equipmentList;

  /// Desired AI narrative verbosity.
  final AiTone aiTone;

  /// How strongly recommendations should bias toward user preferences.
  final double recommendationIntensity;

  ProfilePreferences copyWith({
    bool? ambientBackgroundEnabled,
    bool? reduceMotion,
    bool? reduceFlashing,
    bool? highContrast,
    AmbientMotionMode? ambientMotionMode,
    Set<String>? photographyPreferences,
    Set<String>? activityPreferences,
    String? equipmentList,
    AiTone? aiTone,
    double? recommendationIntensity,
  }) {
    return ProfilePreferences(
      ambientBackgroundEnabled:
          ambientBackgroundEnabled ?? this.ambientBackgroundEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      reduceFlashing: reduceFlashing ?? this.reduceFlashing,
      highContrast: highContrast ?? this.highContrast,
      ambientMotionMode: ambientMotionMode ?? this.ambientMotionMode,
      photographyPreferences:
          photographyPreferences ?? this.photographyPreferences,
      activityPreferences: activityPreferences ?? this.activityPreferences,
      equipmentList: equipmentList ?? this.equipmentList,
      aiTone: aiTone ?? this.aiTone,
      recommendationIntensity:
          recommendationIntensity ?? this.recommendationIntensity,
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
        other.ambientMotionMode == ambientMotionMode &&
        _setEquals(other.photographyPreferences, photographyPreferences) &&
        _setEquals(other.activityPreferences, activityPreferences) &&
        other.equipmentList == equipmentList &&
        other.aiTone == aiTone &&
        other.recommendationIntensity == recommendationIntensity;
  }

  @override
  int get hashCode => Object.hash(
    ambientBackgroundEnabled,
    reduceMotion,
    reduceFlashing,
    highContrast,
    ambientMotionMode,
    Object.hashAllUnordered(photographyPreferences),
    Object.hashAllUnordered(activityPreferences),
    equipmentList,
    aiTone,
    recommendationIntensity,
  );
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
