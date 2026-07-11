import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qiguang/src/app/router.dart';
import 'package:qiguang/src/core/context/context_fixture.dart';
import 'package:qiguang/src/core/context/context_snapshot.dart';

class QiguangApp extends StatelessWidget {
  const QiguangApp({super.key, this.initialContext});

  final ContextSnapshot? initialContext;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: '栖光',
        debugShowCheckedModeBanner: false,
        routerConfig: createQiguangRouter(
          initialContext ?? ContextFixtures.quietCity(),
        ),
      ),
    );
  }
}
