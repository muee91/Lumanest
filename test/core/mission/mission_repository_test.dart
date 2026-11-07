import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/mission/mission_repository.dart';

void main() {
  test('mission draft uses the canonical WGS84 destination contract', () {
    final body = const MissionDraft(
      destinationName: '西湖',
      latitude: 30.24,
      longitude: 120.15,
      intent: 'photography',
      locale: 'zh-CN',
      watchEnabled: true,
    ).toJson();
    expect(body['destination'], {
      'name': '西湖',
      'latitude': 30.24,
      'longitude': 120.15,
      'system': 'wgs84',
    });
    expect(body['watchEnabled'], true);
  });

  test('mission response parsing rejects incomplete remote records', () {
    expect(MissionRemoteSnapshot.fromJson({'id': 'mis_x'}), isNull);
    final parsed = MissionRemoteSnapshot.fromJson({
      'id': 'mis_0123456789abcdef0123456789abcdef',
      'state': 'field',
      'version': 3,
      'watchEnabled': true,
      'endsAt': '2026-11-08T00:00:00Z',
    });
    expect(parsed?.stage, MissionRemoteStage.field);
    expect(parsed?.version, 3);
    expect(parsed?.endsAt, DateTime.utc(2026, 11, 8));
  });
}
