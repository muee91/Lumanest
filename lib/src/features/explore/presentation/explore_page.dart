import 'package:flutter/material.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FoundationPage(
      title: '探索',
      description: '摄影地图将在接入定位后呈现此刻相关的地点。',
      action: '查看附近',
      icon: Icons.explore_outlined,
    );
  }
}

class _FoundationPage extends StatelessWidget {
  const _FoundationPage({
    required this.title,
    required this.description,
    required this.action,
    required this.icon,
  });

  final String title;
  final String description;
  final String action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(description),
            const Spacer(),
            FilledButton(onPressed: () {}, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
