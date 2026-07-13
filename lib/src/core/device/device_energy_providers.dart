import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/device/device_energy.dart';
import 'package:luma_nest/src/infrastructure/device/battery_plus_device_energy_repository.dart';

final deviceEnergyRepositoryProvider = Provider<DeviceEnergyRepository>((ref) {
  return BatteryPlusDeviceEnergyRepository(Battery());
});

final deviceEnergyProvider = FutureProvider<DeviceEnergySnapshot>((ref) async {
  try {
    return await ref.watch(deviceEnergyRepositoryProvider).read();
  } catch (_) {
    return const DeviceEnergySnapshot.unknown();
  }
});
