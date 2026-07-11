import 'package:flutter/material.dart';

class RoutePage extends StatelessWidget {
  const RoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.route_outlined, size: 32),
            const SizedBox(height: 20),
            Text('路线', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('还没有路线。创建后才会展开路线时间轴与沿途分析。'),
            const Spacer(),
            FilledButton(onPressed: () {}, child: const Text('创建路线')),
          ],
        ),
      ),
    );
  }
}
