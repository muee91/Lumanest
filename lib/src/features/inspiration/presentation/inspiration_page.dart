import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/foundation_action_page.dart';

class InspirationPage extends StatelessWidget {
  const InspirationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FoundationActionPage(
      title: '灵感',
      description: '瓶子会收集与此时此地有关的创作纸条。',
      action: '抽一张纸条',
      icon: Icons.lightbulb_outline,
    );
  }
}
