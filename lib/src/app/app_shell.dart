import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.today_outlined), label: '今日'),
    NavigationDestination(icon: Icon(Icons.explore_outlined), label: '探索'),
    NavigationDestination(icon: Icon(Icons.route_outlined), label: '路线'),
    NavigationDestination(icon: Icon(Icons.lightbulb_outline), label: '灵感'),
    NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: _destinations,
      ),
    );
  }
}
