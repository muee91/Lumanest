import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/design/luma_nest_motion.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/sky_opportunity/domain/sky_opportunity.dart';
import 'package:luma_nest/src/features/sky_opportunity/presentation/sky_opportunity_detail_page.dart';
import 'package:luma_nest/src/presentation_v2/explore/v2_explore_page.dart';
import 'package:luma_nest/src/presentation_v2/intelligence/intelligence_overlay_state.dart';
import 'package:luma_nest/src/presentation_v2/intelligence/v2_intelligence_page.dart';
import 'package:luma_nest/src/presentation_v2/opportunity/v2_opportunity_page.dart';
import 'package:luma_nest/src/presentation_v2/profile/v2_profile_page.dart';
import 'package:luma_nest/src/presentation_v2/route/v2_route_page.dart';
import 'package:luma_nest/src/presentation_v2/shell/v2_app_shell.dart';
import 'package:luma_nest/src/presentation_v2/today/v2_today_page.dart';
import 'package:luma_nest/src/shared/widgets/ambient/ambient_debug_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell-today');
final _exploreNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell-explore',
);
final _routeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell-route');
final _profileNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'shell-profile',
);

GoRouter createLumaNestRouter({ContextSnapshot? initialContext}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/today',
    routes: [
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state, navigationShell) {
          return V2AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: shellNavigatorKey,
            routes: [
              GoRoute(
                path: '/today',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  child: V2TodayPage(initialSnapshot: initialContext),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _exploreNavigatorKey,
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (context, state) => _tabPage(
                  state,
                  child: V2ExplorePage(
                    focus: ExploreFocus.fromQuery(
                      state.uri.queryParameters['focus'],
                    ),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _routeNavigatorKey,
            routes: [
              GoRoute(
                path: '/route',
                pageBuilder: (context, state) {
                  final query = state.uri.queryParameters;
                  return _tabPage(
                    state,
                    child: V2RoutePage(
                      destinationName: query['name'],
                      destinationLatitude: double.tryParse(query['lat'] ?? ''),
                      destinationLongitude: double.tryParse(query['lon'] ?? ''),
                      travelMode: query['mode'] == RouteTravelMode.walking.name
                          ? RouteTravelMode.walking
                          : RouteTravelMode.driving,
                    ),
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavigatorKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) =>
                    _tabPage(state, child: const V2ProfilePage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/intelligence',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: IntelligenceOverlayLifecycle(
            child: V2IntelligencePage(
              initialSnapshot: initialContext,
              initialNoteId: state.uri.queryParameters['note'],
            ),
          ),
        ),
      ),
      // Preserve old deep links while the former shell branch is retired.
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/inspiration',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: IntelligenceOverlayLifecycle(
            child: V2IntelligencePage(
              initialSnapshot: initialContext,
              initialNoteId: state.uri.queryParameters['note'],
            ),
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/sky-opportunity/:event/:dayOffset',
        pageBuilder: (context, state) {
          final eventType = switch (state.pathParameters['event']) {
            'sunrise' => SkyOpportunityEventType.sunrise,
            _ => SkyOpportunityEventType.sunset,
          };
          final dayOffset =
              int.tryParse(state.pathParameters['dayOffset'] ?? '') ?? 0;
          return _v2DetailPage(
            state,
            child: SkyOpportunityDetailPage(
              eventType: eventType,
              dayOffset: dayOffset.clamp(0, 1),
            ),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/opportunity/:id',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: V2OpportunityPage(
            sessionId: state.pathParameters['id']!,
            initialSnapshot: initialContext,
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/session/:id',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: V2OpportunityPage(
            sessionId: state.pathParameters['id']!,
            initialSnapshot: initialContext,
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/insight/:id',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: IntelligenceOverlayLifecycle(
            child: V2IntelligencePage(
              initialSnapshot: initialContext,
              initialNoteId: state.pathParameters['id'],
            ),
          ),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/place/:id',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: V2ExplorePage(placeId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/route-detail/:id',
        pageBuilder: (context, state) => _v2DetailPage(
          state,
          child: V2RoutePage(routeId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/settings',
        pageBuilder: (context, state) =>
            _v2DetailPage(state, child: const V2ProfileSettingsPage()),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/style',
        pageBuilder: (context, state) =>
            _v2DetailPage(state, child: const V2ProfileStylePage()),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/library',
        pageBuilder: (context, state) =>
            _v2DetailPage(state, child: const V2ProfileLibraryPage()),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/privacy',
        pageBuilder: (context, state) =>
            _v2DetailPage(state, child: const V2ProfilePrivacyPage()),
      ),
      if (kDebugMode)
        GoRoute(
          parentNavigatorKey: rootNavigatorKey,
          path: '/ambient-debug',
          pageBuilder: (context, state) =>
              _v2DetailPage(state, child: const AmbientDebugPage()),
        ),
    ],
  );
}

CustomTransitionPage<void> _tabPage(
  GoRouterState state, {
  required Widget child,
}) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: LumaNestMotion.tabTransition,
  reverseTransitionDuration: LumaNestMotion.contentExit,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: LumaNestMotion.standard,
        ),
        child: child,
      ),
);

CustomTransitionPage<void> _v2DetailPage(
  GoRouterState state, {
  required Widget child,
}) => CustomTransitionPage<void>(
  key: state.pageKey,
  transitionDuration: LumaNestMotion.containerTransform,
  reverseTransitionDuration: LumaNestMotion.contentExit,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: LumaNestMotion.emphasized,
      reverseCurve: LumaNestMotion.exit,
    );
    return FadeTransition(opacity: curved, child: child);
  },
);

String shootingSessionLocation(String sessionId) =>
    '/session/${Uri.encodeComponent(sessionId)}';

String? shootingSessionIdFrom(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length != 2 || segments.first != 'session') return null;
  final value = segments[1];
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$').hasMatch(value)
      ? value
      : null;
}
