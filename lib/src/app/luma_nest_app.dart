import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/app/router.dart';
import 'package:luma_nest/src/core/context/environment_consent.dart';
import 'package:luma_nest/src/core/context/environment_providers.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/companion/companion_client.dart';
import 'package:luma_nest/src/core/device/device_energy_providers.dart';
import 'package:luma_nest/src/core/feedback/luma_nest_feedback_service.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';
import 'package:luma_nest/src/features/sky_opportunity/application/sky_opportunity_providers.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/features/sky_opportunity/presentation/sky_opportunity_ambient.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_canvas.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_field_parameters.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_composer.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preset.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_rendering_policy.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_visual_mapper.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_preview_override.dart';

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
  String _routeLocation = '/today';
  bool _routeRefreshScheduled = false;
  String? _lastPhotographyWatchReconciliation;
  String? _lastCompanionRefresh;
  AmbientPresetBundle? _ambientPresets;

  /// Becomes true while the user scrolls content so the ambient canvas can
  /// auto-decelerate per design §9.3.
  final ValueNotifier<bool> _interactionSuppressed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(LumaNestFeedbackService.instance.preload());
    unawaited(ref.read(journeyRouteContextRestorerProvider).restore());
    _router = createLumaNestRouter(initialContext: widget.initialContext);
    unawaited(_loadAmbientPresets());
    configureShootingSessionNotificationNavigation(
      ref.read(shootingSessionNotificationServiceProvider),
      _handlePhotographyNotificationResponse,
    );
    _router.routerDelegate.addListener(_handleRouterChange);
  }

  Future<void> _loadAmbientPresets() async {
    try {
      final presets = await AmbientPresetBundle.load(rootBundle);
      if (!mounted) return;
      setState(() => _ambientPresets = presets);
    } on Object {
      // V1 remains the deterministic visual fallback if an asset is missing
      // or malformed. Release builds must not fail to start for ambience.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_handleRouterChange);
    _interactionSuppressed.dispose();
    unawaited(LumaNestFeedbackService.instance.dispose());
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
    final library = ref.watch(userLibraryProvider).asData?.value;
    // Do not reconcile until the persisted preference has been resolved. Using
    // a loading value as `false` here would cancel an already-scheduled local
    // reminder on every cold start before the setting is restored.
    final photographyWatchNotificationsEnabled = ref
        .watch(shootingSessionNotificationsEnabledProvider)
        .asData
        ?.value;
    final reconciliationSnapshot =
        widget.initialContext ?? liveSnapshot?.asData?.value;
    final skyPoint = reconciliationSnapshot?.location;
    final now = ref.watch(currentTimeProvider)();
    final skyOpportunity = skyPoint == null
        ? null
        : ref
              .watch(
                dailySkyOpportunitiesProvider((
                  latitude: skyPoint.latitude,
                  longitude: skyPoint.longitude,
                  focus: skyOpportunityFocusForSnapshot(
                    reconciliationSnapshot!,
                    now,
                  ),
                )),
              )
              .asData
              ?.value
              .activeHomeOpportunity(now);
    if (reconciliationSnapshot != null &&
        _lastCompanionRefresh != reconciliationSnapshot.id) {
      _lastCompanionRefresh = reconciliationSnapshot.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          ref
              .read(companionInventoryProvider.notifier)
              .refresh(
                snapshotId: reconciliationSnapshot.id,
                reason: 'manual_refresh',
                visiblePage: _visiblePage,
              ),
        );
      });
    }
    if (photographyWatchNotificationsEnabled != null &&
        reconciliationSnapshot != null &&
        library != null) {
      final watchIds =
          library.watchedSessions
              .map((watch) => watch.id)
              .toList(growable: false)
            ..sort();
      final reconciliationKey =
          '${photographyWatchNotificationsEnabled ? 'enabled' : 'disabled'}:'
          '${reconciliationSnapshot.id}:${watchIds.join(',')}';
      if (_lastPhotographyWatchReconciliation != reconciliationKey) {
        _lastPhotographyWatchReconciliation = reconciliationKey;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            ref
                .read(shootingSessionNotificationReconcilerProvider)
                .reconcile(snapshot: reconciliationSnapshot, library: library),
          );
        });
      }
    }
    final conserveDeviceEnergy = ref
        .watch(deviceEnergyProvider)
        .asData
        ?.value
        .shouldConserveEnergy;

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
        final ambientRendering = AmbientRenderingPolicy.resolve(
          preferences,
          conserveDeviceEnergy: conserveDeviceEnergy ?? false,
          routeLocation: _routeLocation,
        );
        final previewOverride = kDebugMode
            ? ref.watch(ambientPreviewOverrideProvider)
            : null;
        final ambientSnapshot =
            previewOverride?.snapshot ?? reconciliationSnapshot;
        final ambientVisualState = _ambientVisualState(
          ambientSnapshot,
          skyOpportunity,
        );
        final ambientComposition =
            previewOverride?.composition ??
            _ambientComposition(
              snapshot: ambientSnapshot,
              visualState: ambientVisualState,
              quality: ambientRendering.quality,
              conserveEnergy: conserveDeviceEnergy ?? false,
            );
        final darkStage = _routeLocation.startsWith('/inspiration');
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: darkStage
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: darkStage ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: darkStage
                ? const Color(0xFF17201D)
                : const Color(0xFFF5F5F1),
            systemNavigationBarIconBrightness: darkStage
                ? Brightness.light
                : Brightness.dark,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFFF5F5F1)),
              if (preferences.ambientBackgroundEnabled &&
                  _routeLocation == '/today')
                _TodayAmbientLayer(
                  debugLabel: previewOverride?.label,
                  child: AmbientCanvas(
                    visualState: ambientVisualState,
                    composition: ambientComposition,
                    reduceMotion:
                        ambientRendering.reduceMotion ||
                        systemDisablesAnimations,
                    reduceFlashing: ambientRendering.reduceFlashing,
                    showWeatherTexture: ambientRendering.showWeatherTexture,
                    renderer: ambientRendering.renderer,
                    intensity: ambientRendering.intensity,
                    interactionSuppressed: _interactionSuppressed,
                  ),
                ),
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _interactionSuppressed.value = true;
                  } else if (notification is ScrollEndNotification) {
                    _interactionSuppressed.value = false;
                  }
                  return false;
                },
                child: child ?? const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _visiblePage {
    if (_routeLocation.startsWith('/explore')) return 'explore';
    if (_routeLocation.startsWith('/route')) return 'route';
    if (_routeLocation.startsWith('/inspiration')) return 'inspiration';
    if (_routeLocation.startsWith('/profile')) return 'profile';
    if (_routeLocation.startsWith('/session')) return 'shootingWindow';
    return 'today';
  }

  AmbientVisualState? _ambientVisualState(
    ContextSnapshot? snapshot,
    SkyOpportunityForecast? skyOpportunity,
  ) {
    if (snapshot == null) return null;
    final base = const AmbientVisualMapper().resolveSnapshot(
      snapshot,
      Brightness.light,
    );
    return const SkyOpportunityAmbientMapper().apply(
      base: base,
      snapshot: snapshot,
      forecast: skyOpportunity,
    );
  }

  AmbientVisualComposition? _ambientComposition({
    required ContextSnapshot? snapshot,
    required AmbientVisualState? visualState,
    required AmbientQualityTier quality,
    required bool conserveEnergy,
  }) {
    if (snapshot == null || visualState == null || _ambientPresets == null) {
      return null;
    }
    final preset = _ambientPresets!.select(
      weather: snapshot.weather,
      dayPhase: snapshot.dayPhase,
      conserveEnergy: conserveEnergy || quality == AmbientQualityTier.static,
    );
    return const AmbientComposer().compose(
      visualState: visualState,
      preset: preset,
      quality: quality,
    );
  }

  void _handleRouterChange() {
    if (_routeRefreshScheduled) return;
    _routeRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeRefreshScheduled = false;
      if (!mounted) return;
      final nextLocation = _router.routerDelegate.currentConfiguration.uri.path;
      if (nextLocation == _routeLocation) return;
      setState(() => _routeLocation = nextLocation);
    });
  }

  void _handlePhotographyNotificationResponse(String payload) {
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    final sessionId = shootingSessionIdFrom(uri);
    if (sessionId != null) {
      _router.go(shootingSessionLocation(sessionId));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(deviceEnergyProvider);
    }
  }
}

class _TodayAmbientLayer extends StatelessWidget {
  const _TodayAmbientLayer({required this.child, this.debugLabel});

  final Widget child;
  final String? debugLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: const Key('today-ambient-layer'),
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: constraints.maxHeight * .58,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: .82,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Color(0xF2FFFFFF),
                    Color(0xB8FFFFFF),
                    Colors.transparent,
                  ],
                  stops: [0, .48, .78, 1],
                ).createShader(bounds),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const RadialGradient(
                    center: Alignment(.58, -.88),
                    radius: 1.38,
                    colors: [
                      Colors.white,
                      Color(0xE6FFFFFF),
                      Color(0x9CFFFFFF),
                      Colors.transparent,
                    ],
                    stops: [0, .38, .76, 1],
                  ).createShader(bounds),
                  child: child,
                ),
              ),
            ),
            if (debugLabel != null)
              Positioned(
                top: 246,
                right: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .88),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      '调试预览 · $debugLabel',
                      style: const TextStyle(
                        color: Color(0xFF203A3B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
