import 'package:luma_nest/src/core/location/geo_point.dart';

enum NearbyPlaceCategory {
  viewpoint('机位', '观景台'),
  sunriseCandidate('日出候选', '观景台'),
  nightSkyCandidate('夜空候选', '观景台'),
  waterfront('湖岸', '湖泊'),
  humanity('人文', '古镇'),
  fuel('加油', '加油站'),
  food('吃饭', '餐饮'),
  supply('补给', '超市'),
  parking('停车', '停车场'),
  medical('医疗', '医院');

  const NearbyPlaceCategory(this.label, this.keyword);

  final String label;
  final String keyword;

  /// Multiple provider queries improve recall without hard-coding any place
  /// name. Results remain unverified candidates until the reviewed target
  /// catalogue supplies direction, access and source evidence.
  List<String> get searchKeywords => switch (this) {
    NearbyPlaceCategory.waterfront => const [
      '湖泊',
      '湿地公园',
      '水库',
      '滨江公园',
      '海滨公园',
      '堤岸',
    ],
    NearbyPlaceCategory.sunriseCandidate => const [
      '观海',
      '海滨公园',
      '风车',
      '灯塔',
      '海堤',
      '观景台',
      '湿地公园',
      '堤岸',
      '观潮',
    ],
    NearbyPlaceCategory.nightSkyCandidate => const [
      '观景台',
      '露营地',
      '海滨公园',
      '湿地公园',
    ],
    _ => [keyword],
  };
}

enum NearbyAdministrativeRelation {
  sameDistrict,
  sameCity,
  nearbyRegion,
  unknown,
}

enum NearbyCandidateEvidenceBand { supported, comparable, exploratory }

/// The small, photography-first vocabulary exposed by Explore.
///
/// Each intent resolves to one existing, privacy-preserving nearby query.  It
/// deliberately does not invent a new POI type or turn the map into a
/// navigation directory.
enum ExploreCreativeIntent {
  viewpoint('观景线索', NearbyPlaceCategory.viewpoint),
  water('水岸线索', NearbyPlaceCategory.waterfront),
  humanity('人文街巷', NearbyPlaceCategory.humanity),
  supplies('拍摄补给', NearbyPlaceCategory.supply),
  parking('停车地点', NearbyPlaceCategory.parking),
  food('附近餐饮', NearbyPlaceCategory.food),
  fuel('附近加油', NearbyPlaceCategory.fuel),
  medical('附近医疗', NearbyPlaceCategory.medical);

  const ExploreCreativeIntent(this.label, this.category);

  final String label;
  final NearbyPlaceCategory category;
}

enum ExploreFocus {
  photography('附近摄影线索'),
  sunrise('正在寻找驾车可达的日出候选'),
  nightSky('正在寻找夜空拍摄候选'),
  water('正在寻找湖岸与水面线索'),
  humanity('正在寻找街巷与人文线索'),
  wildlife('正在查看区域野生动物线索');

  const ExploreFocus(this.label);
  final String label;

  static ExploreFocus fromQuery(String? value) => switch (value) {
    'sunrise' => ExploreFocus.sunrise,
    'night-sky' => ExploreFocus.nightSky,
    'water' => ExploreFocus.water,
    'humanity' => ExploreFocus.humanity,
    'wildlife' => ExploreFocus.wildlife,
    _ => ExploreFocus.photography,
  };

  NearbyPlaceCategory get category => switch (this) {
    ExploreFocus.sunrise => NearbyPlaceCategory.sunriseCandidate,
    ExploreFocus.nightSky => NearbyPlaceCategory.nightSkyCandidate,
    ExploreFocus.water => NearbyPlaceCategory.waterfront,
    ExploreFocus.humanity => NearbyPlaceCategory.humanity,
    ExploreFocus.photography ||
    ExploreFocus.wildlife => NearbyPlaceCategory.viewpoint,
  };
}

class NearbyPlaceMedia {
  const NearbyPlaceMedia({
    required this.id,
    required this.url,
    required this.attribution,
    this.title,
    this.creator,
    this.license,
    this.sourceUrl,
    this.matchBasis,
  });

  final String id;
  final String url;
  final String attribution;
  final String? title;
  final String? creator;
  final String? license;
  final String? sourceUrl;
  final String? matchBasis;
}

class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.point,
    required this.distanceMeters,
    this.address,
    this.provinceName,
    this.cityName,
    this.districtName,
    this.matchedKeyword,
    this.administrativeRelation = NearbyAdministrativeRelation.unknown,
    this.drivingDurationSeconds,
    this.drivingDistanceMeters,
    this.sourceEvidenceCount = 0,
    this.aiDiscovered = false,
    this.reviewedTarget = false,
    this.media = const [],
    this.cachedAt,
  });

  final String id;
  final String name;
  final NearbyPlaceCategory category;
  final GeoPoint point;
  final int distanceMeters;
  final String? address;
  final String? provinceName;
  final String? cityName;
  final String? districtName;
  final String? matchedKeyword;
  final NearbyAdministrativeRelation administrativeRelation;
  final int? drivingDurationSeconds;
  final int? drivingDistanceMeters;
  final int sourceEvidenceCount;
  final bool aiDiscovered;
  final bool reviewedTarget;
  final List<NearbyPlaceMedia> media;
  final DateTime? cachedAt;

  bool get isOfflineCache => cachedAt != null;
  NearbyPlaceMedia? get coverMedia => media.firstOrNull;

  NearbyCandidateEvidenceBand get evidenceBand {
    if (drivingDurationSeconds != null &&
        sourceEvidenceCount > 0 &&
        administrativeRelation != NearbyAdministrativeRelation.unknown) {
      return NearbyCandidateEvidenceBand.supported;
    }
    if (drivingDurationSeconds != null &&
        administrativeRelation != NearbyAdministrativeRelation.unknown) {
      return NearbyCandidateEvidenceBand.comparable;
    }
    return NearbyCandidateEvidenceBand.exploratory;
  }

  String? get administrativeLabel => switch ((cityName, districtName)) {
    (final city?, final district?) when city != district => '$city · $district',
    (_, final district?) => district,
    (final city?, _) => city,
    _ => null,
  };

  NearbyPlace copyWith({
    int? drivingDurationSeconds,
    int? drivingDistanceMeters,
    int? sourceEvidenceCount,
    bool? aiDiscovered,
    bool? reviewedTarget,
    List<NearbyPlaceMedia>? media,
    NearbyAdministrativeRelation? administrativeRelation,
    DateTime? cachedAt,
  }) => NearbyPlace(
    id: id,
    name: name,
    category: category,
    point: point,
    distanceMeters: distanceMeters,
    address: address,
    provinceName: provinceName,
    cityName: cityName,
    districtName: districtName,
    matchedKeyword: matchedKeyword,
    administrativeRelation:
        administrativeRelation ?? this.administrativeRelation,
    drivingDurationSeconds:
        drivingDurationSeconds ?? this.drivingDurationSeconds,
    drivingDistanceMeters: drivingDistanceMeters ?? this.drivingDistanceMeters,
    sourceEvidenceCount: sourceEvidenceCount ?? this.sourceEvidenceCount,
    aiDiscovered: aiDiscovered ?? this.aiDiscovered,
    reviewedTarget: reviewedTarget ?? this.reviewedTarget,
    media: media ?? this.media,
    cachedAt: cachedAt ?? this.cachedAt,
  );
}
