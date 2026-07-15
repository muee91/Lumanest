import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/location/geo_point.dart';
import 'package:luma_nest/src/features/route/infrastructure/gpx_track_parser.dart';

void main() {
  const parser = GpxTrackParser();

  test('parses a namespaced GPX track with recorded time and elevation', () {
    final track = parser.parse(
      _bytes('''
        <?xml version="1.0"?>
        <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1">
          <trk>
            <name>山脊晨线</name>
            <trkseg>
              <trkpt lat="30.0000" lon="120.0000">
                <ele>100</ele><time>2026-07-15T01:00:00Z</time>
              </trkpt>
              <trkpt lat="30.0050" lon="120.0050">
                <ele>120</ele><time>2026-07-15T01:05:00Z</time>
              </trkpt>
              <trkpt lat="30.0100" lon="120.0100">
                <ele>115</ele><time>2026-07-15T01:10:00Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
      '''),
      fallbackName: 'fallback.gpx',
      importedAt: DateTime.utc(2026, 7, 15, 2),
    );

    expect(track.name, '山脊晨线');
    expect(track.points, hasLength(3));
    expect(
      track.points
          .singleWhere((point) => point.latitude == 30)
          .coordinateSystem,
      CoordinateSystem.wgs84,
    );
    expect(track.distanceMeters, greaterThan(1000));
    expect(track.durationSeconds, 600);
    expect(track.durationEstimated, isFalse);
    expect(track.ascentMeters, 20);
    expect(track.descentMeters, 5);
  });

  test(
    'falls back to the filename and estimates duration without timestamps',
    () {
      final track = parser.parse(
        _bytes('''
        <gpx version="1.1">
          <rte>
            <rtept lat="30" lon="120" />
            <rtept lat="30.001" lon="120.001" />
          </rte>
        </gpx>
      '''),
        fallbackName: '周末徒步.GPX',
        importedAt: DateTime.utc(2026, 7, 15),
      );

      expect(track.name, '周末徒步');
      expect(track.durationEstimated, isTrue);
      expect(track.durationSeconds, greaterThanOrEqualTo(60));
      expect(track.ascentMeters, isNull);
    },
  );

  test(
    'preserves GPX segment breaks without inventing distance between them',
    () {
      final track = parser.parse(
        _bytes('''
        <gpx><trk>
          <trkseg>
            <trkpt lat="30" lon="120" />
            <trkpt lat="30.001" lon="120.001" />
          </trkseg>
          <trkseg>
            <trkpt lat="40" lon="110" />
            <trkpt lat="40.001" lon="110.001" />
          </trkseg>
        </trk></gpx>
      '''),
        fallbackName: 'segments.gpx',
        importedAt: DateTime.utc(2026, 7, 15),
      );

      expect(track.points, hasLength(4));
      expect(track.segmentBreakIndexes, [2]);
      expect(track.distanceMeters, lessThan(500));
      expect(track.toRoute().polylineSegmentBreakIndexes, [2]);
    },
  );

  test('rejects declarations that can expand external entities', () {
    expect(
      () => parser.parse(
        _bytes('''
          <!DOCTYPE gpx [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
          <gpx version="1.1"><trk><trkseg>
            <trkpt lat="30" lon="120" />
            <trkpt lat="31" lon="121" />
          </trkseg></trk></gpx>
        '''),
        fallbackName: 'unsafe.gpx',
        importedAt: DateTime.utc(2026, 7, 15),
      ),
      throwsA(
        isA<GpxTrackFailure>().having(
          (error) => error.kind,
          'kind',
          GpxTrackFailureKind.invalidDocument,
        ),
      ),
    );
  });

  test('enforces file size and point count limits before persistence', () {
    expect(
      () => const GpxTrackParser(maximumBytes: 4).parse(
        _bytes('<gpx/>'),
        fallbackName: 'large.gpx',
        importedAt: DateTime.utc(2026, 7, 15),
      ),
      throwsA(
        isA<GpxTrackFailure>().having(
          (error) => error.kind,
          'kind',
          GpxTrackFailureKind.tooLarge,
        ),
      ),
    );
    expect(
      () => const GpxTrackParser(maximumPoints: 2).parse(
        _bytes('''
          <gpx><trk><trkseg>
            <trkpt lat="30" lon="120" />
            <trkpt lat="30.1" lon="120.1" />
            <trkpt lat="30.2" lon="120.2" />
          </trkseg></trk></gpx>
        '''),
        fallbackName: 'dense.gpx',
        importedAt: DateTime.utc(2026, 7, 15),
      ),
      throwsA(
        isA<GpxTrackFailure>().having(
          (error) => error.kind,
          'kind',
          GpxTrackFailureKind.tooManyPoints,
        ),
      ),
    );
  });
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value.trim()));
