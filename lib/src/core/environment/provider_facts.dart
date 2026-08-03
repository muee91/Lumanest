import 'package:luma_nest/src/core/location/geo_point.dart';

enum ProviderBundleStatus { ready, partial, unavailable }

enum ProviderStatus { ready, noData, unconfigured, unavailable }

enum ProviderVerification {
  authoritative,
  observed,
  model,
  reference,
  candidate,
}

enum ProviderCategory {
  surface,
  atmosphere,
  operations,
  outdoor,
  culture,
  wildlife,
  fire,
  marine,
  astronomy,
  spaceWeather,
  other,
}

class ProviderFactSource {
  const ProviderFactSource({
    required this.id,
    required this.title,
    required this.publisher,
    required this.url,
    required this.license,
    required this.version,
  });

  final String id;
  final String title;
  final String publisher;
  final Uri url;
  final String license;
  final String version;
}

class ProviderSignal {
  const ProviderSignal({
    required this.id,
    required this.kind,
    required this.category,
    required this.title,
    required this.summary,
    required this.verification,
    required this.observedAt,
    required this.expiresAt,
    required this.sourceUrl,
  });

  final String id;
  final String kind;
  final ProviderCategory category;
  final String title;
  final String summary;
  final ProviderVerification verification;
  final DateTime observedAt;
  final DateTime expiresAt;
  final Uri sourceUrl;

  bool isCurrentAt(DateTime instant) => expiresAt.isAfter(instant);
}

class ProviderFactState {
  const ProviderFactState({
    required this.id,
    required this.category,
    required this.status,
    required this.observedAt,
    required this.expiresAt,
    required this.source,
    required this.signals,
    required this.message,
  });

  final String id;
  final ProviderCategory category;
  final ProviderStatus status;
  final DateTime observedAt;
  final DateTime expiresAt;
  final ProviderFactSource? source;
  final List<ProviderSignal> signals;
  final String? message;

  bool get hasSignals => status == ProviderStatus.ready && signals.isNotEmpty;
}

class ProviderFactsBundle {
  const ProviderFactsBundle({
    required this.requestedCoordinate,
    required this.radiusKm,
    required this.generatedAt,
    required this.expiresAt,
    required this.status,
    required this.cacheStatus,
    required this.providers,
  });

  final GeoPoint requestedCoordinate;
  final int radiusKm;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final ProviderBundleStatus status;
  final String cacheStatus;
  final List<ProviderFactState> providers;

  List<ProviderSignal> get displayableSignals =>
      displayableSignalsAt(DateTime.now().toUtc());

  List<ProviderSignal> displayableSignalsAt(DateTime instant) {
    final now = instant.toUtc();
    final result =
        providers
            .expand(
              (provider) => provider.hasSignals
                  ? provider.signals
                  : const <ProviderSignal>[],
            )
            .where((signal) => signal.isCurrentAt(now))
            .toList(growable: false)
          ..sort((a, b) {
            final verification = _verificationRank(
              a.verification,
            ).compareTo(_verificationRank(b.verification));
            if (verification != 0) return verification;
            return b.observedAt.compareTo(a.observedAt);
          });
    return List.unmodifiable(result);
  }

  bool get hasDisplayableSignals => displayableSignals.isNotEmpty;

  static ProviderFactsBundle fromJson(Map<String, Object?> body) {
    const rootKeys = {
      'contractVersion',
      'requestedCoordinate',
      'radiusKm',
      'generatedAt',
      'expiresAt',
      'status',
      'cacheStatus',
      'providers',
    };
    if (!_exactKeys(body, rootKeys) || body['contractVersion'] != 1) {
      throw const FormatException('Invalid provider facts contract');
    }
    final generatedAt = _date(body['generatedAt']);
    final expiresAt = _date(body['expiresAt']);
    final radiusKm = body['radiusKm'];
    final rawProviders = body['providers'];
    if (!expiresAt.isAfter(generatedAt) ||
        radiusKm is! int ||
        radiusKm < 1 ||
        radiusKm > 50 ||
        rawProviders is! List ||
        rawProviders.length > 14) {
      throw const FormatException('Invalid provider facts metadata');
    }
    final providers = rawProviders
        .map((item) => _provider(_map(item)))
        .toList(growable: false);
    if (providers.map((item) => item.id).toSet().length != providers.length) {
      throw const FormatException('Duplicate provider facts');
    }
    return ProviderFactsBundle(
      requestedCoordinate: _coordinate(body['requestedCoordinate']),
      radiusKm: radiusKm,
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      status: _bundleStatus(body['status']),
      cacheStatus: _cacheStatus(body['cacheStatus']),
      providers: List.unmodifiable(providers),
    );
  }

  static ProviderFactState _provider(Map<String, Object?> value) {
    const keys = {
      'id',
      'category',
      'status',
      'observedAt',
      'expiresAt',
      'source',
      'signals',
      'message',
    };
    if (!_exactKeys(value, keys)) {
      throw const FormatException('Invalid provider state');
    }
    final id = _bounded(value['id'], 1, 64);
    final status = _providerStatus(value['status']);
    final category = _category(value['category']);
    final observedAt = _date(value['observedAt']);
    final expiresAt = _date(value['expiresAt']);
    final rawSignals = value['signals'];
    final source = value['source'] == null
        ? null
        : _source(_map(value['source']));
    final message = value['message'] == null
        ? null
        : _bounded(value['message'], 1, 160);
    if (!expiresAt.isAfter(observedAt) ||
        rawSignals is! List ||
        rawSignals.length > 8) {
      throw const FormatException('Invalid provider freshness');
    }
    final signals = rawSignals
        .map((item) => _signal(_map(item)))
        .toList(growable: false);
    if (status == ProviderStatus.ready && (source == null || signals.isEmpty)) {
      throw const FormatException('Ready provider has no evidence');
    }
    if (status != ProviderStatus.ready && signals.isNotEmpty) {
      throw const FormatException('Inactive provider exposes signals');
    }
    return ProviderFactState(
      id: id,
      category: category,
      status: status,
      observedAt: observedAt,
      expiresAt: expiresAt,
      source: source,
      signals: List.unmodifiable(signals),
      message: message,
    );
  }

  static ProviderSignal _signal(Map<String, Object?> value) {
    const keys = {
      'id',
      'kind',
      'category',
      'title',
      'summary',
      'verification',
      'observedAt',
      'expiresAt',
      'sourceUrl',
    };
    if (!_exactKeys(value, keys)) {
      throw const FormatException('Invalid provider signal');
    }
    final observedAt = _date(value['observedAt']);
    final expiresAt = _date(value['expiresAt']);
    if (!expiresAt.isAfter(observedAt)) {
      throw const FormatException('Invalid provider signal freshness');
    }
    return ProviderSignal(
      id: _bounded(value['id'], 1, 64),
      kind: _bounded(value['kind'], 1, 64),
      category: _category(value['category']),
      title: _bounded(value['title'], 1, 120),
      summary: _bounded(value['summary'], 1, 360),
      verification: _verification(value['verification']),
      observedAt: observedAt,
      expiresAt: expiresAt,
      sourceUrl: _httpsUri(value['sourceUrl']),
    );
  }

  static ProviderFactSource _source(Map<String, Object?> value) {
    const keys = {'id', 'title', 'publisher', 'url', 'license', 'version'};
    if (!_exactKeys(value, keys)) {
      throw const FormatException('Invalid provider source');
    }
    return ProviderFactSource(
      id: _bounded(value['id'], 1, 120),
      title: _bounded(value['title'], 1, 160),
      publisher: _bounded(value['publisher'], 1, 160),
      url: _httpsUri(value['url']),
      license: _bounded(value['license'], 1, 160),
      version: _bounded(value['version'], 1, 120),
    );
  }

  static GeoPoint _coordinate(Object? value) {
    final map = _map(value);
    if (!_exactKeys(map, const {'latitude', 'longitude', 'system'}) ||
        map['system'] != 'wgs84' ||
        !_finite(map['latitude'], -90, 90) ||
        !_finite(map['longitude'], -180, 180)) {
      throw const FormatException('Invalid provider coordinate');
    }
    return GeoPoint(
      latitude: (map['latitude']! as num).toDouble(),
      longitude: (map['longitude']! as num).toDouble(),
      coordinateSystem: CoordinateSystem.wgs84,
    );
  }

  static int _verificationRank(ProviderVerification value) => switch (value) {
    ProviderVerification.authoritative => 0,
    ProviderVerification.observed => 1,
    ProviderVerification.model => 2,
    ProviderVerification.reference => 3,
    ProviderVerification.candidate => 4,
  };
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('Expected object');
  return Map<String, Object?>.from(value);
}

bool _exactKeys(Map<String, Object?> value, Set<String> keys) =>
    value.length == keys.length && value.keys.toSet().containsAll(keys);

String _bounded(Object? value, int minimum, int maximum) {
  if (value is! String ||
      value.length < minimum ||
      value.length > maximum ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value)) {
    throw const FormatException('Invalid provider text');
  }
  return value;
}

DateTime _date(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const FormatException('Invalid provider date');
  }
  final date = DateTime.tryParse(value)?.toUtc();
  if (date == null) throw const FormatException('Invalid provider date');
  return date;
}

Uri _httpsUri(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Invalid provider URL');
  }
  return uri;
}

bool _finite(Object? value, double minimum, double maximum) =>
    value is num && value.isFinite && value >= minimum && value <= maximum;

String _cacheStatus(Object? value) {
  if (value is! String || !const {'miss', 'hit', 'coalesced'}.contains(value)) {
    throw const FormatException('Invalid provider cache status');
  }
  return value;
}

ProviderBundleStatus _bundleStatus(Object? value) => switch (value) {
  'ready' => ProviderBundleStatus.ready,
  'partial' => ProviderBundleStatus.partial,
  'unavailable' => ProviderBundleStatus.unavailable,
  _ => throw const FormatException('Invalid provider bundle status'),
};

ProviderStatus _providerStatus(Object? value) => switch (value) {
  'ready' => ProviderStatus.ready,
  'noData' => ProviderStatus.noData,
  'unconfigured' => ProviderStatus.unconfigured,
  'unavailable' => ProviderStatus.unavailable,
  _ => throw const FormatException('Invalid provider status'),
};

ProviderVerification _verification(Object? value) => switch (value) {
  'authoritative' => ProviderVerification.authoritative,
  'observed' => ProviderVerification.observed,
  'model' => ProviderVerification.model,
  'reference' => ProviderVerification.reference,
  'candidate' => ProviderVerification.candidate,
  _ => throw const FormatException('Invalid provider verification'),
};

ProviderCategory _category(Object? value) => switch (value) {
  'surface' => ProviderCategory.surface,
  'atmosphere' => ProviderCategory.atmosphere,
  'operations' => ProviderCategory.operations,
  'outdoor' => ProviderCategory.outdoor,
  'culture' => ProviderCategory.culture,
  'wildlife' => ProviderCategory.wildlife,
  'fire' => ProviderCategory.fire,
  'marine' => ProviderCategory.marine,
  'astronomy' => ProviderCategory.astronomy,
  'spaceWeather' => ProviderCategory.spaceWeather,
  'other' => ProviderCategory.other,
  _ => throw const FormatException('Invalid provider category'),
};
