/// Canonical local equipment capabilities inferred from the free-form profile
/// equipment list. Parsing is deliberately conservative: unknown text has no
/// effect on a recommendation.
enum EquipmentCapability {
  camera('camera'),
  phoneCamera('phone_camera'),
  tripod('tripod'),
  wideAngle('wide_angle'),
  telephoto('telephoto'),
  fastLens('fast_lens'),
  filter('filter'),
  drone('drone'),
  weatherProtection('weather_protection'),
  headlamp('headlamp');

  const EquipmentCapability(this.id);
  final String id;
}

class EquipmentCapabilityMatch {
  const EquipmentCapabilityMatch({
    required this.available,
    required this.missing,
  });

  final Set<EquipmentCapability> available;
  final Set<EquipmentCapability> missing;

  bool get isReady => missing.isEmpty;
}

abstract final class EquipmentCapabilityParser {
  static Set<EquipmentCapability> parse(String equipmentList) {
    final text = equipmentList.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return const <EquipmentCapability>{};
    final result = <EquipmentCapability>{};
    void add(EquipmentCapability capability, List<String> aliases) {
      if (aliases.any(text.contains)) result.add(capability);
    }

    add(EquipmentCapability.camera, ['相机', 'camera', '机身', '微单', '单反']);
    add(EquipmentCapability.phoneCamera, ['手机', 'iphone', 'pixel', '安卓']);
    add(EquipmentCapability.tripod, ['三脚架', '脚架', 'tripod']);
    add(EquipmentCapability.wideAngle, [
      '广角',
      'wide',
      '14mm',
      '16mm',
      '18mm',
      '20mm',
      '24mm',
    ]);
    add(EquipmentCapability.telephoto, [
      '长焦',
      'tele',
      '70-200',
      '100-400',
      '200mm',
      '300mm',
      '600mm',
    ]);
    add(EquipmentCapability.fastLens, ['大光圈', 'f/1.', 'f1.', 'f/2.', 'f2.']);
    add(EquipmentCapability.filter, ['滤镜', 'nd镜', 'cpl', '偏振']);
    add(EquipmentCapability.drone, ['无人机', 'dji', '航拍']);
    add(EquipmentCapability.weatherProtection, ['雨罩', '防水', '防雨']);
    add(EquipmentCapability.headlamp, ['头灯', '手电', '照明']);
    return Set.unmodifiable(result);
  }

  static EquipmentCapabilityMatch match(
    String equipmentList,
    Iterable<EquipmentCapability> required,
  ) {
    final available = parse(equipmentList);
    final requiredSet = required.toSet();
    return EquipmentCapabilityMatch(
      available: available,
      missing: Set.unmodifiable(requiredSet.difference(available)),
    );
  }

  static Set<String> idsOf(Iterable<EquipmentCapability> capabilities) =>
      Set.unmodifiable(capabilities.map((capability) => capability.id));
}
