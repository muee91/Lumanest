import 'dart:async';

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
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/notifications/application/photography_watch_notification_service.dart';
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

  /// Becomes true while the user scrolls content so the ambient canvas can
  /// auto-decelerate per design §9.3.
  final ValueNotifier<bool> _interactionSuppressed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(journeyRouteContextRestorerProvider).restore());
    _router = createLumaNestRouter(initialContext: widget.initialContext);
    configurePhotographyWatchNotificationNavigation(
      ref.read(photographyWatchNotificationServiceProvider),
      _handlePhotographyNotificationResponse,
    );
    _router.routerDelegate.addListener(_handleRouterChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.routerDelegate.removeListener(_handleRouterChange);
    _interactionSuppressed.dispose();
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
        .watch(photographyWatchNotificationsEnabledProvider)
        .asData
        ?.value;
    final reconciliationSnapshot =
        widget.initialContext ?? liveSnapshot?.asData?.value;
    if (photographyWatchNotificationsEnabled != null &&
        reconciliationSnapshot != null &&
        library != null) {
      final watchIds =
          library.watchedOpportunities
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
                .read(photographyWatchNotificationReconcilerProvider)
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
                renderer: ambientRendering.renderer,
                intensity: ambientRendering.intensity,
                interactionSuppressed: _interactionSuppressed,
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
    if (uri == null ||
        uri.path != '/shooting-window' ||
        uri.queryParameters.keys.any((key) => key != 'opportunity')) {
      return;
    }
    final opportunityId = shootingWindowOpportunityIdFrom(uri);
    if (opportunityId != null) {
      _router.go(shootingWindowLocation(opportunityId));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(deviceEnergyProvider);
    }
  }
}
