import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_shader_surface.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

void main() {
  testWidgets('creates one shader across rebuilds and disposes it with state', (
    tester,
  ) async {
    var created = 0;
    var disposed = 0;
    final visual = const AmbientVisualMapper().resolveSnapshot(
      ContextFixtures.lakeSunset(),
      Brightness.light,
    );

    Widget surface(double time) => MaterialApp(
      home: AmbientShaderSurface(
        visualState: visual,
        time: time,
        onShaderCreated: () => created += 1,
        onShaderDisposed: () => disposed += 1,
        child: const ColoredBox(color: Colors.blue),
      ),
    );

    await tester.pumpWidget(surface(0));
    await tester.pumpAndSettle();
    expect(created, 1);

    await tester.pumpWidget(surface(1));
    await tester.pumpAndSettle();
    expect(created, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed, 1);
  });
}
