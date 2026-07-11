import 'package:flutter/material.dart';
import 'package:luma_nest/src/shared/widgets/foundation_action_page.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FoundationActionPage(
      title: '探索',
      description: '摄影地图将在接入定位后呈现此刻相关的地点。',
      action: '查看附近',
      icon: Icons.explore_outlined,
    );
  }
}
