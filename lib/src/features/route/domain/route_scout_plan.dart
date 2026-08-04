import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/route/domain/route_support_stop.dart';
import 'package:luma_nest/src/features/route/domain/route_weather.dart';

enum RouteScoutNodeKind {
  route,
  safety,
  weather,
  photography,
  fuel,
  supply,
  food,
  parking,
  medical,
}

enum RouteScoutPriority { critical, high, normal }

enum RouteScoutCoverage { full, partial, localOnly }

class RouteScoutNode {
  const RouteScoutNode({
    required this.id,
    required this.kind,
    required this.priority,
    required this.title,
    required this.detail,
    required this.routeProgress,
    required this.expectedAt,
    required this.source,
    this.isStale = false,
    this.place,
  }) : assert(routeProgress >= 0 && routeProgress <= 1);

  final String id;
  final RouteScoutNodeKind kind;
  final RouteScoutPriority priority;
  final String title;
  final String detail;

  /// Approximate corridor progress. It is not a navigation waypoint.
  final double routeProgress;
  final DateTime expectedAt;
  final String source;
  final bool isStale;
  final NearbyPlace? place;

  bool get hasMapTarget => place != null;
}

class RouteScoutPlan {
  RouteScoutPlan({
    required this.routeId,
    required this.generatedAt,
    required this.coverage,
    required Iterable<RouteScoutNode> nodes,
  }) : nodes = List.unmodifiable(nodes);

  final String routeId;
  final DateTime generatedAt;
  final RouteScoutCoverage coverage;
  final List<RouteScoutNode> nodes;

  List<RouteScoutNode> get primaryNodes => nodes.take(3).toList(growable: false);

  int get criticalCount => nodes
      .where((node) => node.priority == RouteScoutPriority.critical)
      .length;

  int get highCount =>
      nodes.where((node) => node.priority == RouteScoutPriority.high).length;

  int get photographyCount => nodes
      .where((node) => node.kind == RouteScoutNodeKind.photography)
      .length;

  int get supportCount => nodes
      .where(
        (node) => switch (node.kind) {
          RouteScoutNodeKind.fuel ||
          RouteScoutNodeKind.supply ||
          RouteScoutNodeKind.food ||
          RouteScoutNodeKind.parking ||
          RouteScoutNodeKind.medical => true,
          _ => false,
        },
      )
      .length;

  String get headline {
    if (criticalCount > 0) return '沿途有需要优先确认的天气风险';
    if (highCount > 0) return '路线可用，先看 $highCount 条重点';
    if (photographyCount > 0) return '路线与拍摄时间窗口有重合';
    if (supportCount > 0) return '沿途信息已经整理好';
    return '路线已准备，沿途暂无额外重点';
  }

  RouteScoutNode? nextAfter(double progress) {
    final floor = (progress - .03).clamp(0.0, 1.0);
    return nodes
        .where((node) => node.routeProgress >= floor)
        .firstOrNull;
  }

  static double progressForJourney({
    required DateTime startedAt,
    required int durationSeconds,
    required DateTime now,
  }) {
    if (durationSeconds <= 0) return 0;
    final elapsed = now.toUtc().difference(startedAt.toUtc()).inSeconds;
    return (elapsed / durationSeconds).clamp(0.0, 1.0);
  }
}

class RouteScoutPlanBuilder {
  const RouteScoutPlanBuilder._();

  static RouteScoutPlan build({
    required String routeId,
    required DrivingRoute route,
    required ContextSnapshot snapshot,
    required DateTime now,
    RouteWeatherReport? weather,
    List<RouteSupportStop> supportStops = const [],
  }) {
    final routeEnd = now.add(Duration(seconds: route.durationSeconds));
    final nodes = <RouteScoutNode>[];

    if (route.isStale) {
      nodes.add(
        RouteScoutNode(
          id: 'route-cache',
          kind: RouteScoutNodeKind.route,
          priority: RouteScoutPriority.high,
          title: '路线来自离线缓存',
          detail: '道路和耗时可能已经变化；开始导航前请让地图重新确认。',
          routeProgress: 0,
          expectedAt: now,
          source: 'device-cache',
          isStale: true,
        ),
      );
    }

    if (weather != null) {
      _appendWeather(nodes, weather);
    }
    _appendPhotography(nodes, snapshot, now, routeEnd, route.durationSeconds);
    _appendSupport(nodes, supportStops, now, route.durationSeconds);

    nodes.sort((first, second) {
      final priority = _priorityRank(first.priority).compareTo(
        _priorityRank(second.priority),
      );
      if (priority != 0) return priority;
      final progress = first.routeProgress.compareTo(second.routeProgress);
      if (progress != 0) return progress;
      return first.expectedAt.compareTo(second.expectedAt);
    });

    final coverage = weather == null
        ? RouteScoutCoverage.localOnly
        : weather.coverage == RouteWeatherCoverage.full &&
              !weather.hasStaleSamples
        ? RouteScoutCoverage.full
        : RouteScoutCoverage.partial;
    return RouteScoutPlan(
      routeId: routeId,
      generatedAt: now.toUtc(),
      coverage: coverage,
      nodes: nodes.take(12),
    );
  }

  static void _appendWeather(
    List<RouteScoutNode> nodes,
    RouteWeatherReport weather,
  ) {
    RouteWeatherCondition? previousCondition;
    var normalTransitionAdded = false;
    for (var index = 0; index < weather.samples.length; index += 1) {
      final sample = weather.samples[index];
      final label = _segmentLabel(sample.progress);
      final weatherDetail = _weatherDetail(sample);
      if (sample.thunder) {
        nodes.add(
          RouteScoutNode(
            id: 'weather-thunder-$index',
            kind: RouteScoutNodeKind.safety,
            priority: RouteScoutPriority.critical,
            title: '$label可能出现雷暴',
            detail: '$weatherDetail；具体安全判断只看安全卡和官方预警。',
            routeProgress: sample.progress,
            expectedAt: sample.expectedAt,
            source: weather.source,
            isStale: sample.stale,
          ),
        );
      } else if (sample.visibilityKm case final visibility?
          when visibility < 5) {
        nodes.add(
          RouteScoutNode(
            id: 'weather-visibility-$index',
            kind: RouteScoutNodeKind.weather,
            priority: RouteScoutPriority.high,
            title: '$label能见度偏低',
            detail: weatherDetail,
            routeProgress: sample.progress,
            expectedAt: sample.expectedAt,
            source: weather.source,
            isStale: sample.stale,
          ),
        );
      } else if (sample.windSpeedMps >= 12) {
        nodes.add(
          RouteScoutNode(
            id: 'weather-wind-$index',
            kind: RouteScoutNodeKind.weather,
            priority: RouteScoutPriority.high,
            title: '$label风力较强',
            detail: weatherDetail,
            routeProgress: sample.progress,
            expectedAt: sample.expectedAt,
            source: weather.source,
            isStale: sample.stale,
          ),
        );
      } else if (sample.precipitationMm >= 2 ||
          const {
            RouteWeatherCondition.rain,
            RouteWeatherCondition.snow,
            RouteWeatherCondition.dust,
          }.contains(sample.condition)) {
        nodes.add(
          RouteScoutNode(
            id: 'weather-condition-$index',
            kind: RouteScoutNodeKind.weather,
            priority: RouteScoutPriority.high,
            title: '$label天气将发生变化',
            detail: weatherDetail,
            routeProgress: sample.progress,
            expectedAt: sample.expectedAt,
            source: weather.source,
            isStale: sample.stale,
          ),
        );
      } else if (!normalTransitionAdded &&
          previousCondition != null &&
          previousCondition != sample.condition) {
        normalTransitionAdded = true;
        nodes.add(
          RouteScoutNode(
            id: 'weather-transition-$index',
            kind: RouteScoutNodeKind.weather,
            priority: RouteScoutPriority.normal,
            title: '$label天气与前段不同',
            detail: weatherDetail,
            routeProgress: sample.progress,
            expectedAt: sample.expectedAt,
            source: weather.source,
            isStale: sample.stale,
          ),
        );
      }
      previousCondition = sample.condition;
    }
  }

  static void _appendPhotography(
    List<RouteScoutNode> nodes,
    ContextSnapshot snapshot,
    DateTime now,
    DateTime routeEnd,
    int durationSeconds,
  ) {
    for (final session in snapshot.shootingSessions.take(3)) {
      if (!session.endsAt.isAfter(now) || session.startsAt.isAfter(routeEnd)) {
        continue;
      }
      final primary = session.phases
              .where((phase) => phase.kind == session.primaryPhase)
              .firstOrNull ??
          session.phases.firstOrNull;
      final targetAt = primary?.peaksAt ?? session.startsAt;
      final seconds = targetAt.difference(now).inSeconds;
      final progress = durationSeconds <= 0
          ? 0.0
          : (seconds / durationSeconds).clamp(0.0, 1.0);
      nodes.add(
        RouteScoutNode(
          id: 'photo-${session.id}',
          kind: RouteScoutNodeKind.photography,
          priority: RouteScoutPriority.normal,
          title: '途中可能遇到「${session.title}」',
          detail: '时间与路线重合，不代表沿途已有验证机位；到点前再看现场与机会详情。',
          routeProgress: progress,
          expectedAt: targetAt,
          source: session.ruleVersion,
          isStale: snapshot.isStale,
        ),
      );
    }
  }

  static void _appendSupport(
    List<RouteScoutNode> nodes,
    List<RouteSupportStop> stops,
    DateTime now,
    int durationSeconds,
  ) {
    final seen = <String>{};
    for (final stop in stops) {
      if (!seen.add(stop.place.id)) continue;
      final kind = _supportKind(stop.place.category);
      if (kind == null) continue;
      final progress = stop.routeProgress.clamp(0.0, 1.0);
      nodes.add(
        RouteScoutNode(
          id: 'support-${stop.place.id}',
          kind: kind,
          priority: RouteScoutPriority.normal,
          title: '${_supportLabel(kind)} · ${stop.place.name}',
          detail:
              '约在路线 ${(progress * 100).round()}% 附近，距采样点 ${_distance(stop.place.distanceMeters)}；'
              '不是导航途经点，出发前请在地图确认。',
          routeProgress: progress,
          expectedAt: now.add(
            Duration(seconds: (durationSeconds * progress).round()),
          ),
          source: stop.isCached ? 'device-cache' : 'AMap',
          isStale: stop.isCached,
          place: stop.place,
        ),
      );
    }
  }

  static int _priorityRank(RouteScoutPriority priority) => switch (priority) {
    RouteScoutPriority.critical => 0,
    RouteScoutPriority.high => 1,
    RouteScoutPriority.normal => 2,
  };

  static String _segmentLabel(double progress) => switch (progress) {
    < .18 => '出发后不久',
    < .45 => '路线前段',
    < .72 => '路线中段',
    < .92 => '路线后段',
    _ => '接近目的地',
  };

  static String _weatherDetail(RouteWeatherSample sample) {
    final parts = <String>[
      _conditionLabel(sample.condition),
      '风速 ${sample.windSpeedMps.toStringAsFixed(1)}m/s',
      if (sample.visibilityKm case final value?)
        '能见度 ${value.toStringAsFixed(0)}km',
      if (sample.precipitationMm > 0)
        '降水 ${sample.precipitationMm.toStringAsFixed(1)}mm',
      if (sample.stale) '数据来自缓存',
    ];
    return parts.join('，');
  }

  static String _conditionLabel(RouteWeatherCondition condition) =>
      switch (condition) {
        RouteWeatherCondition.clear => '晴朗',
        RouteWeatherCondition.cloudy => '多云',
        RouteWeatherCondition.rain => '有雨',
        RouteWeatherCondition.snow => '有雪',
        RouteWeatherCondition.dust => '扬沙或沙尘',
        RouteWeatherCondition.unknown => '天气状态不完整',
      };

  static RouteScoutNodeKind? _supportKind(NearbyPlaceCategory category) =>
      switch (category) {
        NearbyPlaceCategory.fuel => RouteScoutNodeKind.fuel,
        NearbyPlaceCategory.supply => RouteScoutNodeKind.supply,
        NearbyPlaceCategory.food => RouteScoutNodeKind.food,
        NearbyPlaceCategory.parking => RouteScoutNodeKind.parking,
        NearbyPlaceCategory.medical => RouteScoutNodeKind.medical,
        _ => null,
      };

  static String _supportLabel(RouteScoutNodeKind kind) => switch (kind) {
    RouteScoutNodeKind.fuel => '加油',
    RouteScoutNodeKind.supply => '补给',
    RouteScoutNodeKind.food => '吃饭',
    RouteScoutNodeKind.parking => '停车',
    RouteScoutNodeKind.medical => '医疗',
    _ => '沿途',
  };

  static String _distance(int meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(1)}km'
      : '${meters}m';
}
