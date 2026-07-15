import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_repository.dart';

abstract interface class WildlifeDataTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioWildlifeDataTransport implements WildlifeDataTransport {
  DioWildlifeDataTransport(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        url,
        queryParameters: query,
        options: Options(headers: headers),
      );
      if (response.data case final Map body) {
        return Map<String, Object?>.from(body);
      }
      throw const WildlifeFailure(WildlifeFailureKind.response);
    } on WildlifeFailure {
      rethrow;
    } on DioException {
      throw const WildlifeFailure(WildlifeFailureKind.network);
    }
  }
}

class DataBrokerWildlifeRepository implements WildlifeRepository {
  const DataBrokerWildlifeRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final WildlifeDataTransport transport;

  @override
  Future<RegionalWildlifeActivity> fetchRegionalWildlifeActivity(
    GeoPoint location,
  ) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const WildlifeFailure(WildlifeFailureKind.configuration);
    }
    location.validate();
    final body = await transport.get(
      '$brokerBaseUrl/v1/wildlife/nearby',
      query: {
        'location': '${location.longitude},${location.latitude}',
        'radiusKm': '20',
      },
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    if (body['source'] != 'GBIF' || body['taxa'] is! List) {
      throw const WildlifeFailure(WildlifeFailureKind.response);
    }
    final contractVersion = int.tryParse('${body['contractVersion'] ?? 1}');
    if (contractVersion == null || contractVersion < 1 || contractVersion > 2) {
      throw const WildlifeFailure(WildlifeFailureKind.response);
    }
    final taxa = (body['taxa'] as List)
        .whereType<Map>()
        .map((raw) => Map<String, Object?>.from(raw))
        .map(_parseTaxon)
        .whereType<WildlifeTaxon>()
        .toList(growable: false);
    final concentration = _parseConcentration(
      body['historicalRecordConcentration'],
    );
    final qualityPolicy = _parseQualityPolicy(body['qualityPolicy']);
    final datasets = _parseDatasets(body['datasets']);
    final eligibleOccurrenceSampleSize = int.tryParse(
      '${body['eligibleOccurrenceSampleSize'] ?? ''}',
    );
    final datasetReferencesTruncated = body['datasetReferencesTruncated'];
    if (contractVersion == 2 &&
        (concentration == null ||
            qualityPolicy == null ||
            datasets == null ||
            eligibleOccurrenceSampleSize == null ||
            eligibleOccurrenceSampleSize < 0 ||
            datasetReferencesTruncated is! bool)) {
      throw const WildlifeFailure(WildlifeFailureKind.response);
    }
    return RegionalWildlifeActivity(
      contractVersion: contractVersion,
      radiusKilometers: int.tryParse('${body['radiusKm'] ?? ''}') ?? 20,
      occurrenceSampleSize:
          int.tryParse('${body['occurrenceSampleSize'] ?? ''}') ?? 0,
      scannedOccurrenceSampleSize:
          int.tryParse('${body['scannedOccurrenceSampleSize'] ?? ''}') ?? 0,
      eligibleOccurrenceSampleSize: eligibleOccurrenceSampleSize ?? 0,
      datasetReferencesTruncated: datasetReferencesTruncated is bool
          ? datasetReferencesTruncated
          : false,
      qualityPolicy: qualityPolicy,
      historicalRecordConcentration: concentration,
      datasets: datasets ?? const [],
      taxa: taxa,
    );
  }

  WildlifeHistoricalRecordConcentration? _parseConcentration(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final recordsWithMonth = int.tryParse('${raw['recordsWithMonth'] ?? ''}');
    final recordsWithTime = int.tryParse('${raw['recordsWithTime'] ?? ''}');
    if (recordsWithMonth == null ||
        recordsWithMonth < 0 ||
        recordsWithTime == null ||
        recordsWithTime < 0 ||
        raw['months'] is! List ||
        raw['timePeriods'] is! List) {
      return null;
    }
    final rawMonths = raw['months'] as List;
    final months = rawMonths
        .whereType<Map>()
        .map((entry) {
          final month = int.tryParse('${entry['month'] ?? ''}');
          final records = int.tryParse('${entry['records'] ?? ''}');
          if (month == null ||
              month < 1 ||
              month > 12 ||
              records == null ||
              records < 1) {
            return null;
          }
          return WildlifeMonthConcentration(month: month, records: records);
        })
        .whereType<WildlifeMonthConcentration>()
        .toList(growable: false);
    final rawPeriods = raw['timePeriods'] as List;
    final periods = rawPeriods
        .whereType<Map>()
        .map((entry) {
          final period = switch (entry['period']) {
            'dawn' => WildlifeObservationPeriod.dawn,
            'day' => WildlifeObservationPeriod.day,
            'dusk' => WildlifeObservationPeriod.dusk,
            'night' => WildlifeObservationPeriod.night,
            _ => null,
          };
          final records = int.tryParse('${entry['records'] ?? ''}');
          if (period == null || records == null || records < 1) return null;
          return WildlifePeriodConcentration(period: period, records: records);
        })
        .whereType<WildlifePeriodConcentration>()
        .toList(growable: false);
    if (months.length != rawMonths.length ||
        periods.length != rawPeriods.length) {
      return null;
    }
    return WildlifeHistoricalRecordConcentration(
      recordsWithMonth: recordsWithMonth,
      recordsWithTime: recordsWithTime,
      months: months,
      timePeriods: periods,
    );
  }

  WildlifeQualityPolicy? _parseQualityPolicy(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map ||
        raw['acceptedLicenses'] is! List ||
        raw['acceptedBasisOfRecord'] is! List) {
      return null;
    }
    final maximum = int.tryParse(
      '${raw['maximumCoordinateUncertaintyMeters'] ?? ''}',
    );
    final maximumDatasets = int.tryParse(
      '${raw['maximumDatasetReferences'] ?? ''}',
    );
    final excludesIssues = raw['excludesSevereGeospatialIssues'];
    if (maximum == null ||
        maximum < 0 ||
        maximumDatasets == null ||
        maximumDatasets < 1 ||
        excludesIssues is! bool) {
      return null;
    }
    return WildlifeQualityPolicy(
      acceptedLicenses: (raw['acceptedLicenses'] as List)
          .whereType<String>()
          .toList(),
      acceptedBasisOfRecord: (raw['acceptedBasisOfRecord'] as List)
          .whereType<String>()
          .toList(),
      maximumCoordinateUncertaintyMeters: maximum,
      maximumDatasetReferences: maximumDatasets,
      excludesSevereGeospatialIssues: excludesIssues,
    );
  }

  List<WildlifeDatasetReference>? _parseDatasets(Object? raw) {
    if (raw == null) return null;
    if (raw is! List) return null;
    final parsed = raw
        .whereType<Map>()
        .map((entry) {
          final datasetKey = entry['datasetKey'];
          final title = entry['title'];
          final publisher = entry['publisher'];
          final citation = entry['citation'];
          final records = int.tryParse('${entry['records'] ?? ''}');
          final uri = Uri.tryParse('${entry['url'] ?? ''}');
          if (datasetKey is! String ||
              datasetKey.isEmpty ||
              title is! String ||
              title.isEmpty ||
              publisher is! String ||
              publisher.isEmpty ||
              citation is! String ||
              citation.isEmpty ||
              records == null ||
              records < 1 ||
              uri == null ||
              uri.scheme != 'https' ||
              uri.host != 'www.gbif.org' ||
              entry['licenses'] is! List) {
            return null;
          }
          return WildlifeDatasetReference(
            datasetKey: datasetKey,
            title: title,
            publisher: publisher,
            licenses: (entry['licenses'] as List).whereType<String>().toList(),
            records: records,
            citation: citation,
            url: uri,
          );
        })
        .whereType<WildlifeDatasetReference>()
        .toList(growable: false);
    return parsed.length == raw.length ? parsed : null;
  }

  WildlifeTaxon? _parseTaxon(Map<String, Object?> raw) {
    final scientificName = raw['scientificName'];
    if (scientificName is! String || scientificName.isEmpty) return null;
    return WildlifeTaxon(
      scientificName: scientificName,
      group: _parseGroup(raw['animalClass']),
      commonName: raw['commonName'] is String
          ? raw['commonName'] as String
          : null,
      records: int.tryParse('${raw['records'] ?? ''}') ?? 0,
    );
  }

  WildlifeGroup _parseGroup(Object? raw) {
    return switch (raw) {
      'bird' => WildlifeGroup.bird,
      'mammal' => WildlifeGroup.mammal,
      'reptile' => WildlifeGroup.reptile,
      'amphibian' => WildlifeGroup.amphibian,
      'insect' => WildlifeGroup.insect,
      _ => WildlifeGroup.other,
    };
  }
}
