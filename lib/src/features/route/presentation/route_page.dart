import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/foundation_action_page.dart';

class RoutePage extends StatelessWidget {
  const RoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FoundationActionPage(
      title: '路线',
      description: '还没有路线。创建后才会展开路线时间轴与沿途分析。',
      action: '创建路线',
      icon: Icons.route_outlined,
    );
  }
}
