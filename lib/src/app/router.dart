import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/app/app_shell.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/presentation/explore_page.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/inspiration/presentation/inspiration_page.dart';
import 'package:luma_nest/src/features/profile/presentation/profile_page.dart';
import 'package:luma_nest/src/features/route/presentation/route_page.dart';
import 'package:luma_nest/src/features/route/domain/driving_route.dart';
import 'package:luma_nest/src/features/today/presentation/today_page.dart';
import 'package:luma_nest/src/features/shooting_window/presentation/shooting_window_page.dart';

GoRouter createLumaNestRouter({ContextSnapshot? initialContext}) {
  return GoRouter(
    initialLocation: '/today',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: LiveTodayPage(initialSnapshot: initialContext),
                ),
              ),
              GoRoute(
                path: '/shooting-window',
                builder: (context, state) => ShootingWindowPage(
                  initialOpportunityId: shootingWindowOpportunityIdFrom(
                    state.uri,
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: ExplorePage(
                    focus: ExploreFocus.fromQuery(
                      state.uri.queryParameters['focus'],
                    ),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/route',
                pageBuilder: (context, state) {
                  final query = state.uri.queryParameters;
                  return NoTransitionPage(
                    child: RoutePage(
                      destinationName: query['name'],
                      destinationLatitude: double.tryParse(query['lat'] ?? ''),
                      destinationLongitude: double.tryParse(query['lon'] ?? ''),
                      importedTrackId: query['track'],
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
            routes: [
              GoRoute(
                path: '/inspiration',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: InspirationPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ProfilePage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

String shootingWindowLocation(String opportunityId) => Uri(
  path: '/shooting-window',
  queryParameters: {'opportunity': opportunityId},
).toString();

String? shootingWindowOpportunityIdFrom(Uri uri) {
  if (uri.queryParameters.keys.any((key) => key != 'opportunity')) {
    return null;
  }
  final value = uri.queryParameters['opportunity'];
  return value != null && RegExp(r'^photo-[a-z0-9_-]{1,58}$').hasMatch(value)
      ? value
      : null;
}
