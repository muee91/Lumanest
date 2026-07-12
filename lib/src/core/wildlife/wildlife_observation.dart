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
