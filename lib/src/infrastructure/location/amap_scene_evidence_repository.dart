import 'package:dio/dio.dart';
import 'package:luma_nest/src/core/context/scene_classifier.dart';
import 'package:luma_nest/src/core/context/scene_evidence_repository.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

abstract interface class SceneEvidenceTransport {
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  });
}

class DioSceneEvidenceTransport implements SceneEvidenceTransport {
  DioSceneEvidenceTransport(this._dio);
  final Dio _dio;

  @override
  Future<Map<String, Object?>> get(
    String url, {
    required Map<String, String> query,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        url,
        queryParameters: query,
        options: Options(headers: headers),
      );
      if (response.data case final Map body) {
        return Map<String, Object?>.from(body);
      }
      throw const SceneEvidenceFailure(SceneEvidenceFailureKind.response);
    } on SceneEvidenceFailure {
      rethrow;
    } on DioException {
      throw const SceneEvidenceFailure(SceneEvidenceFailureKind.network);
    }
  }
}

class AmapSceneEvidenceRepository implements SceneEvidenceRepository {
  const AmapSceneEvidenceRepository({
    required this.brokerBaseUrl,
    required this.serviceToken,
    required this.transport,
  });

  final String brokerBaseUrl;
  final String serviceToken;
  final SceneEvidenceTransport transport;

  static final _waterTerms = RegExp(r'湖|水库|湿地|河流|江河|海湾|海滩|滩涂');
  static final _mountainTerms = RegExp(
    r'雪山|山峰|山脉|峡谷|垭口|山(?=\s|$)|峰(?=\s|$)|岭(?=\s|$)',
  );
  static final _aridTerms = RegExp(r'沙漠|戈壁|沙地|雅丹');
  static final _settlementTerms = RegExp(r'古镇|古村|村落|村庄|民族村');
  static final _semanticPoiType = RegExp(r'风景|地名|公园|自然');

  @override
  Future<SceneEvidence> fetch(GeoPoint location) async {
    if (brokerBaseUrl.isEmpty || serviceToken.isEmpty) {
      throw const SceneEvidenceFailure(SceneEvidenceFailureKind.configuration);
    }
    final gcj02 = ChinaCoordinateConverter.wgs84ToGcj02(location);
    final body = await transport.get(
      '$brokerBaseUrl/v1/amap/scene-evidence',
      query: {'location': '${gcj02.longitude},${gcj02.latitude}'},
      headers: {'Authorization': 'Bearer $serviceToken'},
    );
    if (body['status'] != '1' || body['regeocode'] is! Map) {
      throw const SceneEvidenceFailure(SceneEvidenceFailureKind.response);
    }
    final regeocode = Map<String, Object?>.from(body['regeocode'] as Map);
    final semanticTexts = <String>[];
    final aois = regeocode['aois'];
    if (aois is List) {
      for (final raw in aois.whereType<Map>()) {
        semanticTexts.add('${raw['name'] ?? ''} ${raw['type'] ?? ''}');
      }
    }
    final pois = regeocode['pois'];
    var poiCount = 0;
    if (pois is List) {
      poiCount = pois.whereType<Map>().length;
      for (final raw in pois.whereType<Map>()) {
        final type = '${raw['type'] ?? ''}';
        if (_semanticPoiType.hasMatch(type)) {
          semanticTexts.add('${raw['name'] ?? ''} $type');
        }
      }
    }
    final semanticContext = semanticTexts.join(' ');
    final water = _waterTerms.hasMatch(semanticContext);
    final mountain = _mountainTerms.hasMatch(semanticContext);
    final arid = _aridTerms.hasMatch(semanticContext);
    final settlement = _settlementTerms.hasMatch(semanticContext);
    final address = regeocode['addressComponent'];
    final hasCityCode =
        address is Map && '${address['citycode'] ?? ''}'.isNotEmpty;
    final natural = water || mountain || arid;

    return SceneEvidence(
      urban: !natural && !settlement && hasCityCode && poiCount >= 10,
      waterBody: water,
      mountainous: mountain,
      aridLand: arid,
      settlement: settlement,
      source: SceneEvidenceSource.amapSemanticEntities,
    );
  }
}
