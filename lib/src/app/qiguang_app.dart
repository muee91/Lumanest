import 'package:flutter/material.dart';

class QiguangApp extends StatelessWidget {
  const QiguangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _FoundationShell(),
    );
  }
}

class _FoundationShell extends StatefulWidget {
  const _FoundationShell();

  @override
  State<_FoundationShell> createState() => _FoundationShellState();
}

class _FoundationShellState extends State<_FoundationShell> {
  int _selectedIndex = 0;

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
      appBar: AppBar(title: const Text('栖光')),
      body: const SizedBox.expand(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: _destinations,
      ),
    );
  }
}
