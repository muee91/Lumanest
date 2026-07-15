enum WildlifeGroup {
  bird('鸟类'),
  mammal('兽类'),
  reptile('爬行类'),
  amphibian('两栖类'),
  insect('昆虫'),
  other('其他野生动物');

  const WildlifeGroup(this.label);

  final String label;
}

class WildlifeTaxon {
  const WildlifeTaxon({
    required this.scientificName,
    required this.group,
    required this.records,
    this.commonName,
  });

  final String scientificName;
  final WildlifeGroup group;
  final String? commonName;
  final int records;
}

enum WildlifeObservationPeriod {
  dawn('晨间'),
  day('白天'),
  dusk('傍晚'),
  night('夜间');

  const WildlifeObservationPeriod(this.label);

  final String label;
}

class WildlifeMonthConcentration {
  const WildlifeMonthConcentration({
    required this.month,
    required this.records,
  });

  final int month;
  final int records;
}

class WildlifePeriodConcentration {
  const WildlifePeriodConcentration({
    required this.period,
    required this.records,
  });

  final WildlifeObservationPeriod period;
  final int records;
}

class WildlifeHistoricalRecordConcentration {
  WildlifeHistoricalRecordConcentration({
    required this.recordsWithMonth,
    required this.recordsWithTime,
    List<WildlifeMonthConcentration> months = const [],
    List<WildlifePeriodConcentration> timePeriods = const [],
  }) : months = List.unmodifiable(months),
       timePeriods = List.unmodifiable(timePeriods);

  final int recordsWithMonth;
  final int recordsWithTime;
  final List<WildlifeMonthConcentration> months;
  final List<WildlifePeriodConcentration> timePeriods;

  String? get summary {
    final labels = <String>[
      if (months case [final first, ...]) '${first.month}月',
      if (timePeriods case [final first, ...]) first.period.label,
    ];
    return labels.isEmpty ? null : labels.join(' · ');
  }
}

class WildlifeDatasetReference {
  WildlifeDatasetReference({
    required this.datasetKey,
    required this.title,
    required this.publisher,
    required this.records,
    required this.citation,
    required this.url,
    List<String> licenses = const [],
  }) : licenses = List.unmodifiable(licenses);

  final String datasetKey;
  final String title;
  final String publisher;
  final List<String> licenses;
  final int records;
  final String citation;
  final Uri url;
}

class WildlifeQualityPolicy {
  WildlifeQualityPolicy({
    required this.maximumCoordinateUncertaintyMeters,
    required this.excludesSevereGeospatialIssues,
    this.maximumDatasetReferences = 0,
    List<String> acceptedLicenses = const [],
    List<String> acceptedBasisOfRecord = const [],
  }) : acceptedLicenses = List.unmodifiable(acceptedLicenses),
       acceptedBasisOfRecord = List.unmodifiable(acceptedBasisOfRecord);

  final List<String> acceptedLicenses;
  final List<String> acceptedBasisOfRecord;
  final int maximumCoordinateUncertaintyMeters;
  final int maximumDatasetReferences;
  final bool excludesSevereGeospatialIssues;
}

class RegionalWildlifeActivity {
  RegionalWildlifeActivity({
    this.contractVersion = 1,
    required this.radiusKilometers,
    required this.occurrenceSampleSize,
    this.scannedOccurrenceSampleSize = 0,
    this.eligibleOccurrenceSampleSize = 0,
    this.datasetReferencesTruncated = false,
    this.qualityPolicy,
    this.historicalRecordConcentration,
    List<WildlifeDatasetReference> datasets = const [],
    List<WildlifeTaxon> taxa = const [],
  }) : datasets = List.unmodifiable(datasets),
       taxa = List.unmodifiable(taxa);

  final int contractVersion;
  final int radiusKilometers;
  final int occurrenceSampleSize;
  final int scannedOccurrenceSampleSize;
  final int eligibleOccurrenceSampleSize;
  final bool datasetReferencesTruncated;
  final WildlifeQualityPolicy? qualityPolicy;
  final WildlifeHistoricalRecordConcentration? historicalRecordConcentration;
  final List<WildlifeDatasetReference> datasets;
  final List<WildlifeTaxon> taxa;

  bool get hasActivity => taxa.isNotEmpty;

  List<WildlifeGroup> get groups {
    final totals = <WildlifeGroup, int>{};
    for (final taxon in taxa) {
      totals.update(
        taxon.group,
        (records) => records + taxon.records,
        ifAbsent: () => taxon.records,
      );
    }
    final groups = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return List.unmodifiable(groups.map((entry) => entry.key));
  }

  int groupRecordCount(WildlifeGroup group) => taxa
      .where((taxon) => taxon.group == group)
      .fold(0, (total, taxon) => total + taxon.records);
}
