import 'package:luma_nest/src/core/context/context_snapshot.dart';

enum NextPhotographyWindowKind { nightSky, sunriseReference }

enum NextPhotographyWindowAction { exploreNightSky, exploreSunrise }

class NextPhotographyWindowDecision {
  const NextPhotographyWindowDecision({
    required this.kind,
    required this.stableId,
    required this.judgement,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.actionLabel,
    required this.action,
  });

  final NextPhotographyWindowKind kind;
  final String stableId;
  final String judgement;
  final String eyebrow;
  final String title;
  final String detail;
  final String timeLabel;
  final String actionLabel;
  final NextPhotographyWindowAction action;
}

/// Chooses a truthful night-time bridge when no stronger structured
/// opportunity or shooting session is active.
///
/// This resolver deliberately never claims a Milky Way window. Context may
/// contain Galactic-centre and Moon geometry, but light-pollution, local
/// horizon, access and reviewed-place evidence are still required.
abstract final class NextPhotographyWindowResolver {
  static NextPhotographyWindowDecision? resolve({
    required ContextSnapshot snapshot,
    required DateTime now,
    required DateTime? nextSunrise,
  }) {
    final instant = now.toUtc();
    if (snapshot.isStale || snapshot.dayPhase != DayPhase.night) return null;
    if (_supportsImmediateNightSky(snapshot)) {
      return NextPhotographyWindowDecision(
        kind: NextPhotographyWindowKind.nightSky,
        stableId: 'night-sky-${_dateKey(instant)}',
        judgement: '夜已经深了，先看此刻的夜空条件。',
        eyebrow: '当前夜空',
        title: '现在可以尝试夜空拍摄。',
        detail: _nightDetail(snapshot),
        timeLabel: '现在 · 当前条件会随环境更新',
        actionLabel: '查看夜间候选',
        action: NextPhotographyWindowAction.exploreNightSky,
      );
    }
    final sunrise = nextSunrise?.toUtc();
    if (sunrise == null ||
        !sunrise.isAfter(instant) ||
        sunrise.difference(instant) > const Duration(hours: 14)) {
      return null;
    }
    return NextPhotographyWindowDecision(
      kind: NextPhotographyWindowKind.sunriseReference,
      stableId: 'sunrise-reference-${_dateKey(sunrise)}',
      judgement: '今晚夜空条件有限，下一次光线变化在日出。',
      eyebrow: '下一次光线变化',
      title: '可以开始准备明日日出。',
      detail: '先看驾车候选，再确认目标地天气与凌晨开放',
      timeLabel: '${_time(sunrise)} 日出 · 待验证',
      actionLabel: '查看驾车候选',
      action: NextPhotographyWindowAction.exploreSunrise,
    );
  }

  static bool _supportsImmediateNightSky(ContextSnapshot snapshot) {
    final precipitation = snapshot.precipitationMillimeters;
    final visibility = snapshot.visibilityKilometers;
    final cloud = snapshot.cloudCoverPercent;
    final wind = snapshot.windSpeedMetersPerSecond;
    final dry = precipitation != null && precipitation <= .1;
    final visible = visibility != null && visibility >= 10;
    final cloudAcceptable = cloud != null
        ? cloud <= 35
        : snapshot.weather == WeatherType.clear;
    final windAcceptable = wind == null || wind <= 10;
    return dry && visible && cloudAcceptable && windAcceptable;
  }

  static String _nightDetail(ContextSnapshot snapshot) {
    final parts = <String>[];
    final cloud = snapshot.cloudCoverPercent;
    if (cloud != null) parts.add('云量约${cloud.round()}%');
    final visibility = snapshot.visibilityKilometers;
    if (visibility != null) parts.add('能见度约${visibility.round()}公里');
    final moon = snapshot.moonIllumination;
    if (moon != null) {
      parts.add(
        moon <= .35
            ? '月光干扰较少'
            : moon <= .70
            ? '月光会影响暗部'
            : '月光较强',
      );
    }
    return parts.isEmpty ? '当前天气只支持短时观察' : parts.take(3).join(' · ');
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
