import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/presentation_v2/shell/v2_object_navigation_dock.dart';

class V2AppShell extends ConsumerWidget {
  const V2AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(profilePreferencesProvider);
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final appTheme = preferences.highContrast
        ? dark
              ? LumaNestTheme.highContrastDark
              : LumaNestTheme.highContrastLight
        : dark
        ? LumaNestTheme.dark
        : LumaNestTheme.light;
    final reduceMotion =
        preferences.reduceMotion || MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the shell's actual layout constraints instead of the inherited
        // MediaQuery. This keeps the navigation mode correct in split views
        // and in widget tests that resize the surface without rebuilding the
        // surrounding MediaQuery.
        final expanded =
            constraints.hasBoundedWidth && constraints.maxWidth >= 900;
        return Theme(
          data: appTheme,
          child: Scaffold(
            backgroundColor: navigationShell.currentIndex == 0
                ? Colors.transparent
                : appTheme.colorScheme.surface,
            extendBody: true,
            // The Explore map is a fixed viewport. Its search keyboard overlays
            // the lower map instead of resizing the whole page and camera surface.
            resizeToAvoidBottomInset: navigationShell.currentIndex != 1,
            body: expanded
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: V2ObjectNavigationDock.expandedLayoutWidth,
                        ),
                        child: navigationShell,
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: V2ObjectNavigationDock(
                          expanded: true,
                          currentIndex: navigationShell.currentIndex,
                          reduceMotion: reduceMotion,
                          onSelected: (index) =>
                              _select(index, navigationShell),
                          onIntelligence: () => _openIntelligence(context),
                        ),
                      ),
                    ],
                  )
                : navigationShell,
            bottomNavigationBar: expanded
                ? null
                : V2ObjectNavigationDock(
                    currentIndex: navigationShell.currentIndex,
                    reduceMotion: reduceMotion,
                    onSelected: (index) => _select(index, navigationShell),
                    onIntelligence: () => _openIntelligence(context),
                  ),
          ),
        );
      },
    );
  }

  static void _select(int index, StatefulNavigationShell navigationShell) {
    unawaited(HapticFeedback.selectionClick());
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  static void _openIntelligence(BuildContext context) {
    unawaited(HapticFeedback.mediumImpact());
    context.push('/intelligence');
  }
}
