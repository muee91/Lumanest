import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/device/device_energy.dart';

void main() {
  test('system power save mode always requests energy conservation', () {
    const snapshot = DeviceEnergySnapshot(
      batteryLevel: 80,
      isCharging: true,
      isPowerSaveMode: true,
    );

    expect(snapshot.shouldConserveEnergy, isTrue);
  });

  test('low discharging battery requests energy conservation', () {
    const snapshot = DeviceEnergySnapshot(
      batteryLevel: 20,
      isCharging: false,
      isPowerSaveMode: false,
    );

    expect(snapshot.shouldConserveEnergy, isTrue);
  });

  test('charging or unknown battery state does not force a downgrade', () {
    const charging = DeviceEnergySnapshot(
      batteryLevel: 10,
      isCharging: true,
      isPowerSaveMode: false,
    );

    expect(charging.shouldConserveEnergy, isFalse);
    expect(const DeviceEnergySnapshot.unknown().shouldConserveEnergy, isFalse);
  });
}
