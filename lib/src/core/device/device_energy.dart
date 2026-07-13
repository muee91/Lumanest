class DeviceEnergySnapshot {
  const DeviceEnergySnapshot({
    required this.batteryLevel,
    required this.isCharging,
    required this.isPowerSaveMode,
  });

  const DeviceEnergySnapshot.unknown()
    : batteryLevel = null,
      isCharging = null,
      isPowerSaveMode = false;

  final int? batteryLevel;
  final bool? isCharging;
  final bool isPowerSaveMode;

  bool get shouldConserveEnergy {
    if (isPowerSaveMode) return true;
    final level = batteryLevel;
    return level != null && level <= 20 && isCharging == false;
  }
}

abstract interface class DeviceEnergyRepository {
  Future<DeviceEnergySnapshot> read();
}
