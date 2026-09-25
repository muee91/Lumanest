enum SkyOpportunityEventType { sunrise, sunset }

/// Keeps the bounded daily request centred on the next useful light window.
/// The server still owns the final request budget and fallback behaviour.
enum SkyOpportunityDailyFocus { next, preSunrise }

enum SkyOpportunityConfidence { high, medium, low, unavailable }

enum SkyOpportunityAgreement { strong, partial, conflict, singleModel, none }

class SkyOpportunityModelForecast {
  const SkyOpportunityModelForecast({
    required this.model,
    required this.providerLabel,
    required this.eventTime,
    required this.status,
    required this.parseStatus,
  });

  final String model;
  final String? providerLabel;
  final DateTime? eventTime;
  final String status;
  final String parseStatus;
}

class SkyOpportunityPresentation {
  const SkyOpportunityPresentation({
    required this.proactiveEligible,
    required this.paperEligible,
    required this.notificationEligible,
    required this.ambientStrength,
  });

  final bool proactiveEligible;
  final bool paperEligible;
  final bool notificationEligible;

  /// Server-bounded creative contribution in the inclusive 0–0.25 range.
  final double ambientStrength;
}

class SkyOpportunityForecast {
  const SkyOpportunityForecast({
    required this.id,
    required this.requestedCity,
    required this.resolvedCity,
    required this.eventType,
    required this.dayOffset,
    required this.eventTime,
    required this.providerLocalTimeZone,
    required this.level,
    required this.label,
    required this.confidence,
    required this.agreement,
    required this.primaryReason,
    required this.clarityLevel,
    required this.clarityLabel,
    required this.models,
    required this.fetchedAt,
    required this.expiresAt,
    required this.cacheStatus,
    required this.isStale,
    required this.providerStatus,
    required this.attribution,
    required this.presentation,
  });

  final String id;
  final String requestedCity;
  final String resolvedCity;
  final SkyOpportunityEventType eventType;
  final int dayOffset;
  final DateTime? eventTime;
  final String providerLocalTimeZone;
  final String level;
  final String label;
  final SkyOpportunityConfidence confidence;
  final SkyOpportunityAgreement agreement;
  final String primaryReason;
  final String clarityLevel;
  final String clarityLabel;
  final List<SkyOpportunityModelForecast> models;
  final DateTime fetchedAt;
  final DateTime expiresAt;
  final String cacheStatus;
  final bool isStale;
  final String providerStatus;
  final String attribution;
  final SkyOpportunityPresentation presentation;

  bool isMissedAt(DateTime now) =>
      eventTime == null ||
      now.isAfter(eventTime!.add(const Duration(minutes: 90)));

  bool isProactivelyVisibleAt(DateTime now) =>
      presentation.proactiveEligible && !isMissedAt(now);

  String get eventLabel =>
      eventType == SkyOpportunityEventType.sunset ? '晚霞' : '朝霞';

  String get agreementLabel => switch (agreement) {
    SkyOpportunityAgreement.strong => '较一致',
    SkyOpportunityAgreement.partial => '有一定分歧',
    SkyOpportunityAgreement.conflict => '分歧较大',
    SkyOpportunityAgreement.singleModel => '仅单模型',
    SkyOpportunityAgreement.none => '暂无判断',
  };
}

class SkyOpportunityFeatureFlags {
  const SkyOpportunityFeatureFlags({
    this.providerEnabled = false,
    this.cardEnabled = false,
    this.mapEnabled = false,
  });

  final bool providerEnabled;
  final bool cardEnabled;
  final bool mapEnabled;
}

class DailySkyOpportunities {
  const DailySkyOpportunities({
    this.todaySunrise,
    this.todaySunset,
    this.tomorrowSunrise,
    this.tomorrowSunset,
    this.locationUnsupported = false,
    this.flags = const SkyOpportunityFeatureFlags(),
  });

  final SkyOpportunityForecast? todaySunrise;
  final SkyOpportunityForecast? todaySunset;
  final SkyOpportunityForecast? tomorrowSunrise;
  final SkyOpportunityForecast? tomorrowSunset;
  final bool locationUnsupported;
  final SkyOpportunityFeatureFlags flags;

  factory DailySkyOpportunities.unavailable() => const DailySkyOpportunities();

  Iterable<SkyOpportunityForecast> get values => [
    todaySunrise,
    todaySunset,
    tomorrowSunrise,
    tomorrowSunset,
  ].whereType<SkyOpportunityForecast>();

  SkyOpportunityForecast? activeHomeOpportunity(DateTime now) {
    final candidates =
        values
            .where((item) => item.isProactivelyVisibleAt(now))
            .toList(growable: false)
          ..sort((left, right) {
            final leftTime = left.eventTime ?? DateTime(9999);
            final rightTime = right.eventTime ?? DateTime(9999);
            return leftTime.compareTo(rightTime);
          });
    return candidates.firstOrNull;
  }
}
