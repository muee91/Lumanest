import 'package:battery_plus/battery_plus.dart';
import 'package:battery_plus_platform_interface/battery_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/infrastructure/device/battery_plus_device_energy_repository.dart';

void main() {
  late BatteryPlatform original;

  setUp(() {
    original = BatteryPlatform.instance;
  });

  tearDown(() {
    BatteryPlatform.instance = original;
  });

  test('maps level, charging state and power save mode', () async {
    BatteryPlatform.instance = _FakeBatteryPlatform(
      level: 18,
      state: BatteryState.discharging,
      powerSaveMode: true,
    );

    final snapshot = await BatteryPlusDeviceEnergyRepository(Battery()).read();

    expect(snapshot.batteryLevel, 18);
    expect(snapshot.isCharging, isFalse);
    expect(snapshot.isPowerSaveMode, isTrue);
  });

  test('plugin failures remain an optional unknown hint', () async {
    BatteryPlatform.instance = _ThrowingBatteryPlatform();

    final snapshot = await BatteryPlusDeviceEnergyRepository(Battery()).read();

    expect(snapshot.batteryLevel, isNull);
    expect(snapshot.isCharging, isNull);
    expect(snapshot.isPowerSaveMode, isFalse);
    expect(snapshot.shouldConserveEnergy, isFalse);
  });
}

class _FakeBatteryPlatform extends BatteryPlatform {
  _FakeBatteryPlatform({
    required this.level,
    required this.state,
    required this.powerSaveMode,
  });

  final int level;
  final BatteryState state;
  final bool powerSaveMode;

  @override
  Future<int> get batteryLevel async => level;

  @override
  Future<BatteryState> get batteryState async => state;

  @override
  Future<bool> get isInBatterySaveMode async => powerSaveMode;
}

class _ThrowingBatteryPlatform extends BatteryPlatform {
  @override
  Future<int> get batteryLevel => Future.error(StateError('unavailable'));

  @override
  Future<BatteryState> get batteryState =>
      Future.error(StateError('unavailable'));

  @override
  Future<bool> get isInBatterySaveMode =>
      Future.error(StateError('unavailable'));
}
