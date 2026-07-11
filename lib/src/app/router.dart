import 'package:go_router/go_router.dart';
import 'package:qiguang/src/app/app_shell.dart';
import 'package:qiguang/src/core/context/context_snapshot.dart';
import 'package:qiguang/src/core/manifest/manifest_policy.dart';
import 'package:qiguang/src/features/explore/presentation/explore_page.dart';
import 'package:qiguang/src/features/inspiration/presentation/inspiration_page.dart';
import 'package:qiguang/src/features/profile/presentation/profile_page.dart';
import 'package:qiguang/src/features/route/presentation/route_page.dart';
import 'package:qiguang/src/features/today/presentation/today_page.dart';

GoRouter createQiguangRouter(ContextSnapshot snapshot) {
  final manifest = ManifestPolicy.build(snapshot);

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
                    NoTransitionPage(child: TodayPage(manifest: manifest)),
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
