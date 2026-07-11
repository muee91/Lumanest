import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/app/app_shell.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/presentation/explore_page.dart';
import 'package:luma_nest/src/features/inspiration/presentation/inspiration_page.dart';
import 'package:luma_nest/src/features/profile/presentation/profile_page.dart';
import 'package:luma_nest/src/features/route/presentation/route_page.dart';
import 'package:luma_nest/src/features/today/presentation/today_page.dart';

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
                pageBuilder: (context, state) =>
                    NoTransitionPage(
                      child: LiveTodayPage(initialSnapshot: initialContext),
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ExplorePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/route',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: RoutePage()),
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
