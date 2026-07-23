import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/feedback/luma_nest_feedback_service.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shell/v2_object_navigation_dock.dart';

class V2AppShell extends ConsumerWidget {
  const V2AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(profilePreferencesProvider);
    return Theme(
      data: preferences.highContrast
          ? LumaNestTheme.highContrastLight
          : LumaNestTheme.light,
      child: Scaffold(
        backgroundColor: navigationShell.currentIndex == 0
            ? Colors.transparent
            : V2Palette.canvas,
        extendBody: true,
        // The Explore map is a fixed viewport. Its search keyboard overlays
        // the lower map instead of resizing the whole page and camera surface.
        resizeToAvoidBottomInset: navigationShell.currentIndex != 1,
        body: navigationShell,
        bottomNavigationBar: V2ObjectNavigationDock(
          currentIndex: navigationShell.currentIndex,
          reduceMotion:
              preferences.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
          onSelected: (index) => _select(index, navigationShell),
          onIntelligence: () => _openIntelligence(context),
        ),
      ),
    );
  }

  static void _select(int index, StatefulNavigationShell navigationShell) {
    LumaNestFeedbackService.instance.play(
      LumaNestSound.changeCard,
      volume: .18,
      haptic: LumaNestHaptic.selection,
    );
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  static void _openIntelligence(BuildContext context) {
    LumaNestFeedbackService.instance.play(
      LumaNestSound.paper,
      volume: .18,
      haptic: LumaNestHaptic.mediumImpact,
    );
    context.push('/intelligence');
  }
}
