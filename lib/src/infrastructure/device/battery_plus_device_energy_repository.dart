import 'package:battery_plus/battery_plus.dart';
import 'package:luma_nest/src/core/device/device_energy.dart';

class BatteryPlusDeviceEnergyRepository implements DeviceEnergyRepository {
  BatteryPlusDeviceEnergyRepository(this._battery);

  final Battery _battery;

  @override
  Future<DeviceEnergySnapshot> read() async {
    int? level;
    bool? charging;
    var powerSaveMode = false;

    try {
      final value = await _battery.batteryLevel;
      if (value >= 0 && value <= 100) level = value;
    } catch (_) {
      // Device energy is an optional performance hint.
    }
    try {
      final state = await _battery.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {
      // A missing charging state must not force a downgrade.
    }
    try {
      powerSaveMode = await _battery.isInBatterySaveMode;
    } catch (_) {
      // Unsupported platforms keep the user's selected rendering mode.
    }

    return DeviceEnergySnapshot(
      batteryLevel: level,
      isCharging: charging,
      isPowerSaveMode: powerSaveMode,
    );
  }
}
