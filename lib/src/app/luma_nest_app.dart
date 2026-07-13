import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/app/router.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/device/device_energy_providers.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_rendering_policy.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';

class LumaNestApp extends StatelessWidget {
  const LumaNestApp({super.key, this.initialContext});

  final ContextSnapshot? initialContext;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: _LumaNestRoot(initialContext: initialContext));
  }
}

class _LumaNestRoot extends ConsumerStatefulWidget {
  const _LumaNestRoot({required this.initialContext});

  final ContextSnapshot? initialContext;

  @override
  ConsumerState<_LumaNestRoot> createState() => _LumaNestRootState();
}

class _LumaNestRootState extends ConsumerState<_LumaNestRoot>
    with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = createLumaNestRouter(initialContext: widget.initialContext);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(profilePreferencesProvider);
    final consentGranted = ref.watch(environmentConsentProvider);
    final liveSnapshot = widget.initialContext == null && consentGranted
        ? ref.watch(environmentSnapshotProvider)
        : null;
    final conserveDeviceEnergy = ref
        .watch(deviceEnergyProvider)
        .asData
        ?.value
        .shouldConserveEnergy;
    final ambientRendering = AmbientRenderingPolicy.resolve(
      preferences,
      conserveDeviceEnergy: conserveDeviceEnergy ?? false,
    );

    return MaterialApp.router(
      title: '栖光',
      debugShowCheckedModeBanner: false,
      theme: preferences.highContrast
          ? LumaNestTheme.highContrastLight
          : LumaNestTheme.light,
      darkTheme: preferences.highContrast
          ? LumaNestTheme.highContrastDark
          : LumaNestTheme.dark,
      highContrastTheme: LumaNestTheme.highContrastLight,
      highContrastDarkTheme: LumaNestTheme.highContrastDark,
      routerConfig: _router,
      builder: (context, child) {
        final systemDisablesAnimations = MediaQuery.disableAnimationsOf(
          context,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            if (preferences.ambientBackgroundEnabled)
              AmbientCanvas(
                visualState: _ambientVisualState(
                  context,
                  widget.initialContext ?? _snapshotValue(liveSnapshot),
                ),
                reduceMotion:
                    ambientRendering.reduceMotion || systemDisablesAnimations,
                reduceFlashing: ambientRendering.reduceFlashing,
                showWeatherTexture: ambientRendering.showWeatherTexture,
              ),
            ?child,
          ],
        );
      },
    );
  }

  AmbientVisualState? _ambientVisualState(
    BuildContext context,
    ContextSnapshot? snapshot,
  ) {
    if (snapshot == null) return null;
    return const AmbientVisualMapper().resolveSnapshot(
      snapshot,
      Theme.of(context).brightness,
    );
  }

  ContextSnapshot? _snapshotValue(AsyncValue<ContextSnapshot>? snapshot) {
    return snapshot?.when(
      data: (value) => value,
      loading: () => null,
      error: (_, _) => null,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(deviceEnergyProvider);
    }
  }
}
