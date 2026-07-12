enum WildlifeGroup { bird, mammal, reptile, amphibian, insect, other }

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

class RegionalWildlifeActivity {
  RegionalWildlifeActivity({
    required this.radiusKilometers,
    required this.occurrenceSampleSize,
    List<WildlifeTaxon> taxa = const [],
  }) : taxa = List.unmodifiable(taxa);

  final int radiusKilometers;
  final int occurrenceSampleSize;
  final List<WildlifeTaxon> taxa;

  bool get hasActivity => taxa.isNotEmpty;
}
