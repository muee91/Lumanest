import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_composer.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_v2_shader_surface.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rain shaders use continuous lane opacity instead of grid-cell bands',
    () {
      for (final path in [
        'shaders/lumanest_ambient.frag',
        'shaders/lumanest_ambient_v2.frag',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('distanceToLane'));
        expect(source, contains('opacity'));
        expect(source, isNot(contains('noise(floor(cell))')));
        expect(source, isNot(contains('fieldNoise(floor(cell))')));
      }
    },
  );

  testWidgets('V2 shader surface loads and keeps a stable widget contract', (
    tester,
  ) async {
    final bundle = await AmbientPresetBundle.load(rootBundle);
    final snapshot = ContextFixtures.lakeSunset();
    final visual = const AmbientVisualMapper().resolveSnapshot(
      snapshot,
      Brightness.light,
    );
    final composition = const AmbientComposer().compose(
      visualState: visual,
      preset: bundle.require('clear_sunset'),
      quality: AmbientQualityTier.balanced,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AmbientV2ShaderSurface(
          field: composition.field,
          time: 0,
          child: const ColoredBox(color: Color(0xFF123456)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AmbientV2ShaderSurface), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: AmbientV2ShaderSurface(
          field: composition.field,
          time: 1,
          child: const ColoredBox(color: Color(0xFF123456)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AmbientV2ShaderSurface), findsOneWidget);
  });
}
