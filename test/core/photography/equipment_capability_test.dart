import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/photography/equipment_capability.dart';

void main() {
  test('parses conservative equipment capabilities from local free text', () {
    final capabilities = EquipmentCapabilityParser.parse(
      '微单、16mm f1.8、70-200、三脚架、CPL、头灯',
    );

    expect(
      capabilities,
      containsAll(<EquipmentCapability>[
        EquipmentCapability.camera,
        EquipmentCapability.wideAngle,
        EquipmentCapability.telephoto,
        EquipmentCapability.fastLens,
        EquipmentCapability.tripod,
        EquipmentCapability.filter,
        EquipmentCapability.headlamp,
      ]),
    );
  });

  test('unknown equipment text does not invent capabilities', () {
    expect(EquipmentCapabilityParser.parse('一块备用电池和保温杯'), isEmpty);
  });

  test('matches required capabilities without uploading profile text', () {
    final match = EquipmentCapabilityParser.match('相机、24mm、三脚架', [
      EquipmentCapability.camera,
      EquipmentCapability.wideAngle,
      EquipmentCapability.telephoto,
    ]);

    expect(match.available, contains(EquipmentCapability.tripod));
    expect(match.missing, {EquipmentCapability.telephoto});
    expect(match.isReady, isFalse);
    expect(
      EquipmentCapabilityParser.idsOf(match.available),
      containsAll(<String>['camera', 'wide_angle', 'tripod']),
    );
  });
}
