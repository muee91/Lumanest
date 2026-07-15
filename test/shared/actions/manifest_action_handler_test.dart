import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/manifest/ui_manifest.dart';
import 'package:luma_nest/src/shared/actions/manifest_action_handler.dart';

void main() {
  testWidgets('malformed whitelisted action reports expiry instead of no-op', (
    tester,
  ) async {
    const item = ManifestItem(
      id: 'astronomy-without-url',
      title: '天象目录',
      action: ManifestAction.openAuthority,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => handleManifestAction(context, item),
              child: const Text('执行'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('执行'));
    await tester.pump();

    expect(find.text('这个动作已失效，请刷新情境后重试'), findsOneWidget);
  });
}
