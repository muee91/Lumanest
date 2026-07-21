import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/features/explore/application/region_brief_providers.dart';

void main() {
  test('automatic region brief load starts after notifier initialization', () async {
    final container = ProviderContainer(
      overrides: [
        environmentSnapshotProvider.overrideWith(
          _FixedEnvironmentController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(regionBriefControllerProvider).status,
      RegionBriefLoadStatus.idle,
    );
    await pumpEventQueue();

    expect(
      container.read(regionBriefControllerProvider).status,
      RegionBriefLoadStatus.degraded,
    );
  });
}

class _FixedEnvironmentController extends LiveEnvironmentController {
  @override
  Future<ContextSnapshot> build() async => ContextFixtures.quietCity();
}
