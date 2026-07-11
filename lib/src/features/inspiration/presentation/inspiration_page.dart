import 'package:flutter/material.dart';

class InspirationPage extends StatelessWidget {
  const InspirationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, size: 32),
            const SizedBox(height: 20),
            Text('灵感', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            const Text('瓶子会收集与此时此地有关的创作纸条。'),
            const Spacer(),
            FilledButton(onPressed: () {}, child: const Text('抽一张纸条')),
          ],
        ),
      ),
    );
  }
}
