import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/domain/imported_route_track.dart';
import 'package:xml/xml.dart';

enum GpxTrackFailureKind {
  unreadable,
  tooLarge,
  tooManyPoints,
  invalidDocument,
  noTrackPoints,
}

class GpxTrackFailure implements Exception {
  const GpxTrackFailure(this.kind);

  final GpxTrackFailureKind kind;

  @override
  String toString() => 'GpxTrackFailure($kind)';
}

class GpxTrackParser {
  const GpxTrackParser({
    this.maximumBytes = 5 * 1024 * 1024,
    this.maximumPoints = 20000,
  });

  final int maximumBytes;
  final int maximumPoints;

  ImportedRouteTrack parse(
    Uint8List bytes, {
    required String fallbackName,
    required DateTime importedAt,
  }) {
    if (bytes.length > maximumBytes) {
      throw const GpxTrackFailure(GpxTrackFailureKind.tooLarge);
    }

    late final String source;
    late final XmlDocument document;
    try {
      source = utf8.decode(bytes);
      if (RegExp(
        r'<!\s*(DOCTYPE|ENTITY)',
        caseSensitive: false,
      ).hasMatch(source)) {
        throw const GpxTrackFailure(GpxTrackFailureKind.invalidDocument);
      }
      document = XmlDocument.parse(source);
    } on GpxTrackFailure {
      rethrow;
    } on Object {
      throw const GpxTrackFailure(GpxTrackFailureKind.invalidDocument);
    }

    if (document.rootElement.name.local != 'gpx') {
      throw const GpxTrackFailure(GpxTrackFailureKind.invalidDocument);
    }

    final trackElements = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'trkpt')
        .toList(growable: false);
    final routeElements = trackElements.isEmpty
        ? document.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'rtept')
              .toList(growable: false)
        : const <XmlElement>[];
    final pointCount = trackElements.isEmpty
        ? routeElements.length
        : trackElements.length;
    if (pointCount > maximumPoints) {
      throw const GpxTrackFailure(GpxTrackFailureKind.tooManyPoints);
    }

    final trackSegments = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'trkseg')
        .map(
          (segment) => segment.childElements
              .where((element) => element.name.local == 'trkpt')
              .toList(growable: false),
        )
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final rawSegments = trackElements.isEmpty
        ? [routeElements]
        : trackSegments.isEmpty
        ? [trackElements]
        : trackSegments;
    final parsed = <_ParsedPoint>[];
    final segmentBreakIndexes = <int>[];
    for (final elements in rawSegments) {
      final segment = <_ParsedPoint>[];
      for (final element in elements) {
        final latitude = double.tryParse(_attribute(element, 'lat') ?? '');
        final longitude = double.tryParse(_attribute(element, 'lon') ?? '');
        if (latitude == null ||
            longitude == null ||
            !latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          throw const GpxTrackFailure(GpxTrackFailureKind.invalidDocument);
        }
        final elevation = double.tryParse(_childText(element, 'ele') ?? '');
        final timestamp = DateTime.tryParse(_childText(element, 'time') ?? '');
        final point = _ParsedPoint(
          point: GeoPoint(latitude: latitude, longitude: longitude),
          elevation: elevation?.isFinite == true ? elevation : null,
          recordedAt: timestamp?.toUtc(),
        );
        if (segment.isEmpty ||
            !_sameLocation(segment.last.point, point.point)) {
          segment.add(point);
        }
      }
      if (segment.length < 2) continue;
      if (parsed.isNotEmpty) segmentBreakIndexes.add(parsed.length);
      parsed.addAll(segment);
    }
    if (parsed.length < 2) {
      throw const GpxTrackFailure(GpxTrackFailureKind.noTrackPoints);
    }

    var distance = 0.0;
    var ascent = 0.0;
    var descent = 0.0;
    var hasElevationPair = false;
    final breakSet = segmentBreakIndexes.toSet();
    for (var index = 1; index < parsed.length; index++) {
      if (breakSet.contains(index)) continue;
      distance += _distanceMeters(parsed[index - 1].point, parsed[index].point);
      final previousElevation = parsed[index - 1].elevation;
      final elevation = parsed[index].elevation;
      if (previousElevation == null || elevation == null) continue;
      hasElevationPair = true;
      final delta = elevation - previousElevation;
      if (delta > 0) {
        ascent += delta;
      } else {
        descent -= delta;
      }
    }
    if (distance < 1) {
      throw const GpxTrackFailure(GpxTrackFailureKind.noTrackPoints);
    }

    final recordedTimes = parsed
        .map((point) => point.recordedAt)
        .whereType<DateTime>()
        .toList(growable: false);
    final recordedDuration = recordedTimes.length < 2
        ? null
        : recordedTimes.last.difference(recordedTimes.first);
    final hasUsableDuration =
        recordedDuration != null &&
        recordedDuration.inSeconds >= 1 &&
        recordedDuration <= const Duration(days: 30);
    final durationSeconds = hasUsableDuration
        ? recordedDuration.inSeconds
        : math.max(60, (distance / 1.2).round());

    return ImportedRouteTrack(
      id: 'track_${sha256.convert(bytes).toString().substring(0, 24)}',
      name: _trackName(document, fallbackName),
      importedAt: importedAt.toUtc(),
      points: parsed.map((point) => point.point).toList(growable: false),
      segmentBreakIndexes: segmentBreakIndexes,
      distanceMeters: distance.round(),
      durationSeconds: durationSeconds,
      durationEstimated: !hasUsableDuration,
      ascentMeters: hasElevationPair ? ascent.round() : null,
      descentMeters: hasElevationPair ? descent.round() : null,
    );
  }

  String _trackName(XmlDocument document, String fallbackName) {
    final track = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'trk')
        .firstOrNull;
    final route = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rte')
        .firstOrNull;
    final embedded = _normalizeName(_childText(track ?? route, 'name'));
    final fallback = _normalizeName(
      fallbackName
          .replaceFirst(RegExp(r'\.gpx$', caseSensitive: false), '')
          .trim(),
    );
    final name = embedded.isNotEmpty
        ? embedded
        : fallback.isNotEmpty
        ? fallback
        : '导入轨迹';
    return name.length <= 120 ? name : name.substring(0, 120);
  }

  String _normalizeName(String? value) => (value ?? '')
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? _attribute(XmlElement element, String localName) => element
      .attributes
      .where((attribute) => attribute.name.local == localName)
      .firstOrNull
      ?.value;

  static String? _childText(XmlElement? element, String localName) => element
      ?.childElements
      .where((child) => child.name.local == localName)
      .firstOrNull
      ?.innerText;

  static bool _sameLocation(GeoPoint first, GeoPoint second) =>
      first.latitude == second.latitude && first.longitude == second.longitude;

  static double _distanceMeters(GeoPoint first, GeoPoint second) {
    const earthRadius = 6371000.0;
    final lat1 = first.latitude * math.pi / 180;
    final lat2 = second.latitude * math.pi / 180;
    final deltaLat = (second.latitude - first.latitude) * math.pi / 180;
    final deltaLon = (second.longitude - first.longitude) * math.pi / 180;
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _ParsedPoint {
  const _ParsedPoint({
    required this.point,
    required this.elevation,
    required this.recordedAt,
  });

  final GeoPoint point;
  final double? elevation;
  final DateTime? recordedAt;
}
