import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/profile_preferences_controller.dart';

/// Local profile settings surface.
///
/// Phase 1 exposes only the accessibility switches. Collections, routes and
/// devices are intentionally absent until real data sources exist — no empty
/// groups or placeholder counts are rendered.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(profilePreferencesProvider);
    final controller = ref.read(profilePreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('动态背景'),
            value: preferences.ambientBackgroundEnabled,
            onChanged: (_) => controller.toggleAmbientBackground(),
          ),
          SwitchListTile(
            title: const Text('减少动效'),
            value: preferences.reduceMotion,
            onChanged: (_) => controller.toggleReduceMotion(),
          ),
          SwitchListTile(
            title: const Text('减少闪烁'),
            value: preferences.reduceFlashing,
            onChanged: (_) => controller.toggleReduceFlashing(),
          ),
        ],
      ),
    );
  }
}
