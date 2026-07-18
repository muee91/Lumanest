import 'package:luma_nest/src/core/context/context_snapshot.dart';

class ShootingWindow {
  const ShootingWindow({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
    required this.description,
  });

  final String id;
  final String label;
  final DateTime start;
  final DateTime end;
  final String description;

  bool isActiveAt(DateTime moment) =>
      !moment.isBefore(start) && moment.isBefore(end);
}

abstract final class ShootingWindowTimeline {
  static List<ShootingWindow> build(ContextSnapshot snapshot) {
    return fromSolar(sunrise: snapshot.sunrise, sunset: snapshot.sunset);
  }

  static List<ShootingWindow> fromSolar({
    required DateTime? sunrise,
    required DateTime? sunset,
  }) {
    if (sunrise == null || sunset == null) return const [];
    return [
      ShootingWindow(
        id: 'dawn',
        label: '晨光窗口',
        start: sunrise.subtract(const Duration(minutes: 45)),
        end: sunrise.add(const Duration(minutes: 20)),
        description: '适合观察低角度光线、城市轮廓和山体受光变化。',
      ),
      ShootingWindow(
        id: 'sunset',
        label: '落日窗口',
        start: sunset.subtract(const Duration(minutes: 45)),
        end: sunset.add(const Duration(minutes: 20)),
        description: '提前到达机位，观察侧光、逆光和云层变化。',
      ),
      ShootingWindow(
        id: 'blue-hour',
        label: '蓝调窗口',
        start: sunset.add(const Duration(minutes: 20)),
        end: sunset.add(const Duration(hours: 1)),
        description: '适合平衡环境蓝色与城市灯光，实际长度随季节变化。',
      ),
    ];
  }
}
