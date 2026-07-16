import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = <_NavigationItem>[
    _NavigationItem('今日', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
    _NavigationItem('探索', Icons.explore_outlined, Icons.explore_rounded),
    _NavigationItem('路线', Icons.route_outlined, Icons.route_rounded),
    _NavigationItem(
      '灵感',
      Icons.auto_awesome_outlined,
      Icons.auto_awesome_rounded,
    ),
    _NavigationItem('我的', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .84)
                      : const Color(0xFFF3E9D9).withValues(alpha: .84),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .64),
                  ),
                ),
                child: SizedBox(
                  key: const Key('app-bottom-navigation'),
                  height: 62,
                  child: Row(
                    children: [
                      for (var index = 0; index < _destinations.length; index++)
                        Expanded(
                          child: _NavigationButton(
                            item: _destinations[index],
                            selected: index == navigationShell.currentIndex,
                            onTap: () => navigationShell.goBranch(
                              index,
                              initialLocation:
                                  index == navigationShell.currentIndex,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 7, bottom: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: color,
                size: 22,
              ),
              Text(
                item.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 15 : 4,
                height: 2,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
