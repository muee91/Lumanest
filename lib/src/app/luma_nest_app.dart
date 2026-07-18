import 'dart:async';

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
  String _routeLocation = '/today';
  bool _routeRefreshScheduled = false;
  String? _lastPhotographyWatchReconciliation;
  String? _lastCompanionRefresh;

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
    configureShootingSessionNotificationNavigation(
      ref.read(shootingSessionNotificationServiceProvider),
      _handlePhotographyNotificationResponse,
    );
    _router.routerDelegate.addListener(_handleRouterChange);
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
                  child: AmbientCanvas(
                    visualState: _ambientVisualState(
                      widget.initialContext ?? _snapshotValue(liveSnapshot),
                      skyOpportunity,
                    ),
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

  ContextSnapshot? _snapshotValue(AsyncValue<ContextSnapshot>? snapshot) {
    return snapshot?.when(
      data: (value) => value,
      loading: () => null,
      error: (_, _) => null,
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
  const _TodayAmbientLayer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: const Key('today-ambient-layer'),
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: constraints.maxHeight * .44,
        width: double.infinity,
        child: Opacity(
          opacity: .58,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Color(0xF2FFFFFF),
                Color(0x8CFFFFFF),
                Colors.transparent,
              ],
              stops: [0, .4, .72, 1],
            ).createShader(bounds),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const RadialGradient(
                center: Alignment(.58, -.88),
                radius: 1.38,
                colors: [
                  Colors.white,
                  Color(0xE6FFFFFF),
                  Color(0x73FFFFFF),
                  Colors.transparent,
                ],
                stops: [0, .34, .7, 1],
              ).createShader(bounds),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
