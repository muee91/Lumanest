import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/app/router.dart';
import 'package:luma_nest/src/core/context/context_fixture.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';

class LumaNestApp extends StatelessWidget {
  const LumaNestApp({super.key, this.initialContext});

  final ContextSnapshot? initialContext;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _LumaNestRoot(
        initialContext: initialContext ?? ContextFixtures.quietCity(),
      ),
    );
  }
}

class _LumaNestRoot extends ConsumerStatefulWidget {
  const _LumaNestRoot({required this.initialContext});

  final ContextSnapshot initialContext;

  @override
  ConsumerState<_LumaNestRoot> createState() => _LumaNestRootState();
}

class _LumaNestRootState extends ConsumerState<_LumaNestRoot> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createLumaNestRouter(widget.initialContext);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(profilePreferencesProvider);

    return MaterialApp.router(
      title: '栖光',
      debugShowCheckedModeBanner: false,
      theme: LumaNestTheme.light,
      darkTheme: LumaNestTheme.dark,
      routerConfig: _router,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (preferences.ambientBackgroundEnabled)
              AmbientCanvas(
                reduceMotion: preferences.reduceMotion,
                reduceFlashing: preferences.reduceFlashing,
              ),
            ?child,
          ],
        );
      },
    );
  }
}
