import 'dart:async';

import 'package:flutter/services.dart';
import 'package:luma_nest/src/core/location/china_coordinate_converter.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';

/// A single, native AMap location result.
///
/// AMap emits GCJ-02 in mainland China. The gateway converts it immediately
/// so every downstream weather, solar and wildlife calculation stays WGS84.
class AmapLocationFix {
  const AmapLocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.recordedAt,
    this.altitudeMeters,
  });

  final GeoPoint point;
  final double accuracyMeters;
  final DateTime recordedAt;
  final double? altitudeMeters;
}

abstract interface class AmapLocationGateway {
  Future<AmapLocationFix?> getCurrentPosition();
}

class MethodChannelAmapLocationGateway implements AmapLocationGateway {
  const MethodChannelAmapLocationGateway({required this.androidApiKey});

  final String androidApiKey;

  static const _channel = MethodChannel('com.muee.lumanest/amap_location');

  @override
  Future<AmapLocationFix?> getCurrentPosition() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getCurrentPosition',
      <String, Object?>{'apiKey': androidApiKey},
    );
    if (raw == null) return null;

    final latitude = _number(raw['latitude']);
    final longitude = _number(raw['longitude']);
    final accuracy = _number(raw['accuracy']);
    final timestamp = _number(raw['timestamp']);
    if (latitude == null ||
        longitude == null ||
        accuracy == null ||
        timestamp == null) {
      return null;
    }

    final gcj02 = GeoPoint(
      latitude: latitude,
      longitude: longitude,
      coordinateSystem: CoordinateSystem.gcj02,
    ).validate();
    return AmapLocationFix(
      point: ChinaCoordinateConverter.gcj02ToWgs84(gcj02),
      accuracyMeters: accuracy,
      altitudeMeters: _number(raw['altitude']),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
    );
  }

  double? _number(Object? value) => switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
}
