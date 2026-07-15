import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/wildlife/wildlife_observation.dart';

void main() {
  test(
    'regional activity aggregates visible animal groups without locations',
    () {
      final activity = RegionalWildlifeActivity(
        radiusKilometers: 20,
        occurrenceSampleSize: 5,
        taxa: const [
          WildlifeTaxon(
            scientificName: 'Passer montanus',
            group: WildlifeGroup.bird,
            records: 3,
          ),
          WildlifeTaxon(
            scientificName: 'Lutra lutra',
            group: WildlifeGroup.mammal,
            records: 2,
          ),
        ],
      );

      expect(activity.groups, [WildlifeGroup.bird, WildlifeGroup.mammal]);
      expect(activity.groupRecordCount(WildlifeGroup.bird), 3);
      expect(activity.groupRecordCount(WildlifeGroup.mammal), 2);
    },
  );

  test('historical concentration wording describes records, not activity', () {
    final concentration = WildlifeHistoricalRecordConcentration(
      recordsWithMonth: 9,
      recordsWithTime: 6,
      months: const [
        WildlifeMonthConcentration(month: 10, records: 5),
        WildlifeMonthConcentration(month: 9, records: 4),
      ],
      timePeriods: const [
        WildlifePeriodConcentration(
          period: WildlifeObservationPeriod.dusk,
          records: 4,
        ),
      ],
    );

    expect(concentration.summary, '10月 · 傍晚');
  });
}
