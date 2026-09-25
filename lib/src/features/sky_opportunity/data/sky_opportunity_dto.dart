import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';

Map<String, Object?>? _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

double? _double(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

SkyOpportunityConfidence _confidence(Object? value) => switch (value) {
  'high' => SkyOpportunityConfidence.high,
  'medium' => SkyOpportunityConfidence.medium,
  'low' => SkyOpportunityConfidence.low,
  _ => SkyOpportunityConfidence.unavailable,
};

SkyOpportunityAgreement _agreement(Object? value) => switch (value) {
  'strong' => SkyOpportunityAgreement.strong,
  'partial' => SkyOpportunityAgreement.partial,
  'conflict' => SkyOpportunityAgreement.conflict,
  'single_model' => SkyOpportunityAgreement.singleModel,
  _ => SkyOpportunityAgreement.none,
};

bool _hasLegacyFields({
  required Map<String, Object?> location,
  required Map<String, Object?> summary,
  required Map<String, Object?> atmosphere,
  required List<Object?> models,
}) {
  const locationFields = {'latitude', 'longitude'};
  const summaryFields = {'score', 'normalizedScore', 'confidenceScore'};
  const atmosphereFields = {'aod'};
  const modelFields = {'score', 'aod', 'aodLabel'};
  return location.keys.any(locationFields.contains) ||
      summary.keys.any(summaryFields.contains) ||
      atmosphere.keys.any(atmosphereFields.contains) ||
      models.any((value) {
        final model = _map(value);
        return model != null && model.keys.any(modelFields.contains);
      });
}

SkyOpportunityForecast? parseSkyOpportunityEnvelope(Object? value) {
  final envelope = _map(value);
  if (envelope?['status'] != 'ok') return null;
  return parseSkyOpportunity(envelope?['data']);
}

SkyOpportunityForecast? parseSkyOpportunity(Object? value) {
  final body = _map(value);
  final location = _map(body?['location']);
  final event = _map(body?['event']);
  final summary = _map(body?['summary']);
  final atmosphere = _map(body?['atmosphere']);
  final freshness = _map(body?['freshness']);
  final provider = _map(body?['provider']);
  final presentation = _map(body?['presentation']);
  final models = body?['models'];
  final eventType = switch (event?['type']) {
    'sunrise' => SkyOpportunityEventType.sunrise,
    'sunset' => SkyOpportunityEventType.sunset,
    _ => null,
  };
  final fetchedAt = _date(freshness?['fetchedAt']);
  final expiresAt = _date(freshness?['expiresAt']);
  if (body == null ||
      location == null ||
      event == null ||
      summary == null ||
      atmosphere == null ||
      freshness == null ||
      provider == null ||
      presentation == null ||
      models is! List ||
      body['id'] is! String ||
      eventType == null ||
      event['dayOffset'] is! int ||
      event['providerLocalTimeZone'] is! String ||
      fetchedAt == null ||
      expiresAt == null ||
      location['requestedCity'] is! String ||
      location['resolvedCity'] is! String ||
      summary['level'] is! String ||
      summary['label'] is! String ||
      summary['confidence'] is! String ||
      summary['agreement'] is! String ||
      summary['primaryReason'] is! String ||
      atmosphere['clarityLevel'] is! String ||
      atmosphere['clarityLabel'] is! String ||
      freshness['cacheStatus'] is! String ||
      freshness['isStale'] is! bool ||
      provider['providerStatus'] is! String ||
      provider['attribution'] is! String ||
      presentation['proactiveEligible'] is! bool ||
      presentation['paperEligible'] is! bool ||
      presentation['notificationEligible'] is! bool) {
    return null;
  }
  if (_hasLegacyFields(
    location: location,
    summary: summary,
    atmosphere: atmosphere,
    models: models,
  )) {
    return null;
  }
  final ambientStrength = _double(presentation['ambientStrength']);
  if (ambientStrength == null || ambientStrength < 0 || ambientStrength > .25) {
    return null;
  }
  if (models.length > 2) {
    return null;
  }
  final parsedModels = <SkyOpportunityModelForecast>[];
  for (final value in models) {
    final model = _map(value);
    if (model == null ||
        model['model'] is! String ||
        model['status'] is! String ||
        model['parseStatus'] is! String) {
      return null;
    }
    parsedModels.add(
      SkyOpportunityModelForecast(
        model: model['model']! as String,
        providerLabel: model['providerLabel'] as String?,
        eventTime: _date(model['eventTime']),
        status: model['status']! as String,
        parseStatus: model['parseStatus']! as String,
      ),
    );
  }
  return SkyOpportunityForecast(
    id: body['id']! as String,
    requestedCity: location['requestedCity']! as String,
    resolvedCity: location['resolvedCity']! as String,
    eventType: eventType,
    dayOffset: event['dayOffset']! as int,
    eventTime: _date(event['eventTime']),
    providerLocalTimeZone: event['providerLocalTimeZone']! as String,
    level: summary['level']! as String,
    label: summary['label']! as String,
    confidence: _confidence(summary['confidence']),
    agreement: _agreement(summary['agreement']),
    primaryReason: summary['primaryReason']! as String,
    clarityLevel: atmosphere['clarityLevel']! as String,
    clarityLabel: atmosphere['clarityLabel']! as String,
    models: List.unmodifiable(parsedModels),
    fetchedAt: fetchedAt,
    expiresAt: expiresAt,
    cacheStatus: freshness['cacheStatus']! as String,
    isStale: freshness['isStale']! as bool,
    providerStatus: provider['providerStatus']! as String,
    attribution: provider['attribution']! as String,
    presentation: SkyOpportunityPresentation(
      proactiveEligible: presentation['proactiveEligible']! as bool,
      paperEligible: presentation['paperEligible']! as bool,
      notificationEligible: presentation['notificationEligible']! as bool,
      ambientStrength: ambientStrength,
    ),
  );
}

DailySkyOpportunities parseDailySkyOpportunities(Map<String, Object?> body) {
  final flags = _map(body['featureFlags']);
  final envelopes = [
    _map(body['todaySunrise']),
    _map(body['todaySunset']),
    _map(body['tomorrowSunrise']),
    _map(body['tomorrowSunset']),
  ];
  final unsupported = envelopes.whereType<Map<String, Object?>>().any(
    (item) => item['locationUnsupported'] == true,
  );
  return DailySkyOpportunities(
    todaySunrise: parseSkyOpportunityEnvelope(body['todaySunrise']),
    todaySunset: parseSkyOpportunityEnvelope(body['todaySunset']),
    tomorrowSunrise: parseSkyOpportunityEnvelope(body['tomorrowSunrise']),
    tomorrowSunset: parseSkyOpportunityEnvelope(body['tomorrowSunset']),
    locationUnsupported: unsupported,
    flags: SkyOpportunityFeatureFlags(
      providerEnabled: flags?['sunsetbotProviderEnabled'] == true,
      cardEnabled: flags?['skyOpportunityCardEnabled'] == true,
      mapEnabled: flags?['skyOpportunityMapEnabled'] == true,
    ),
  );
}
