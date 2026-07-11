import 'package:flutter/material.dart';
import 'package:luma_nest/src/design/luma_nest_spacing.dart';

class FoundationActionPage extends StatelessWidget {
  const FoundationActionPage({
    super.key,
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
        padding: const EdgeInsets.all(LumaNestSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: LumaNestSpacing.xl),
            const SizedBox(height: LumaNestSpacing.lg),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: LumaNestSpacing.sm),
            Text(description),
            const Spacer(),
            FilledButton(onPressed: () {}, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
