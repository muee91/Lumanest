import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/manifest/creative_personalization.dart';
import 'package:luma_nest/src/core/manifest/manifest_providers.dart';
import 'package:luma_nest/src/core/monitoring/app_logger.dart';

void main() {
  test('manifest provider logs counts without event ids or preferences', () {
    final records = <LogRecord>[];
    final container = ProviderContainer(
      overrides: [
        creativePersonalizationProvider.overrideWithValue(
          CreativePersonalization.neutral,
        ),
        appLoggerProvider.overrideWithValue(AppLogger(sink: records.add)),
      ],
    );
    addTearDown(container.dispose);
    final snapshot = ContextFixtures.lakeSunset();

    final manifest = container.read(personalizedManifestProvider(snapshot));

    final record = records.single;
    expect(record.event, 'manifest.built');
    expect(record.data, {
      LogDataKey.scene: snapshot.primaryScene.name,
      LogDataKey.eventCount: manifest.creativeItems.length,
      LogDataKey.safetyCount: manifest.safety.length,
    });
    expect(record.toString(), isNot(contains(snapshot.id)));
    expect(record.toString(), isNot(contains('reflection')));
    expect(record.toString(), isNot(contains('fingerprint')));
  });
}
