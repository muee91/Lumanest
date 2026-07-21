import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/features/library/application/user_library_controller.dart';
import 'package:luma_nest/src/features/library/domain/user_library.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/features/profile/domain/profile_preferences.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_stage.dart';

class V2ProfilePage extends ConsumerWidget {
  const V2ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(profilePreferencesProvider);
    final library = ref.watch(userLibraryProvider);
    return V2PageStage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          V2TopLine(
            primary: '我的栖光',
            secondary: '个人内容与记录',
            trailing: V2Pressable(
              key: const Key('v2-profile-settings-entry'),
              onTap: () => showProfileSettingsPanel(context),
              compact: true,
              semanticLabel: '打开设置',
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  CupertinoIcons.gear,
                  color: V2Palette.ink,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            flex: 5,
            child: _V2UnderstandingObject(
              preferences: preferences,
              library: library.asData?.value,
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 18),
          V2Pressable(
            onTap: () => context.push('/profile/library'),
            color: V2Palette.paper,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Icon(CupertinoIcons.archivebox, color: V2Palette.moss),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '我留下的',
                      style: TextStyle(
                        color: V2Palette.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, color: V2Palette.mutedInk),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showProfileSettingsPanel(BuildContext context) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭设置',
      barrierColor: Colors.black.withValues(alpha: .52),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const _ProfileSettingsPanel(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

class _ProfileSettingsPanel extends StatelessWidget {
  const _ProfileSettingsPanel();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: (width * .82).clamp(300, 390),
        height: double.infinity,
        child: Material(
          color: V2Palette.paper,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 18, 22, 24),
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 74,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Text(
                      '设置',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _panelEntry(
                  context,
                  icon: CupertinoIcons.slider_horizontal_3,
                  title: '我的观看方式',
                  detail: '题材、行动方式、器材和 AI 表达密度',
                  route: '/profile/style',
                ),
                _panelEntry(
                  context,
                  icon: CupertinoIcons.lock_shield,
                  title: '隐私与感受',
                  detail: '动态、高对比、匿名反馈和本地活动清理',
                  route: '/profile/privacy',
                ),
                _panelEntry(
                  context,
                  icon: CupertinoIcons.archivebox,
                  title: '我留下的',
                  detail: '地点、纸条和拍摄记录',
                  route: '/profile/library',
                ),
                _panelEntry(
                  context,
                  icon: CupertinoIcons.info,
                  title: '关于栖光',
                  detail: '版本与产品说明',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: '栖光',
                    applicationLegalese: '环境感知摄影助手',
                  ),
                ),
                if (kDebugMode)
                  _panelEntry(
                    context,
                    icon: CupertinoIcons.lab_flask,
                    title: '动态背景实验室',
                    detail: '仅开发调试可见',
                    route: '/ambient-debug',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelEntry(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    String? route,
    VoidCallback? onTap,
  }) => InkWell(
    onTap:
        onTap ??
        () {
          Navigator.of(context).pop();
          if (route != null) context.push(route);
        },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: V2Palette.line)),
      ),
      child: Row(
        children: [
          Icon(icon, color: V2Palette.ink, size: 23),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            CupertinoIcons.chevron_right,
            color: V2Palette.line,
            size: 19,
          ),
        ],
      ),
    ),
  );
}

class _V2UnderstandingObject extends StatelessWidget {
  const _V2UnderstandingObject({
    required this.preferences,
    required this.library,
  });
  final ProfilePreferences preferences;
  final UserLibraryState? library;

  @override
  Widget build(BuildContext context) {
    final genres = preferences.photographyPreferences;
    final activities = preferences.activityPreferences;
    final headline = genres.isEmpty
        ? '我还在认识你的观看方式。'
        : '我知道你更容易被${genres.take(2).join('与')}吸引。';
    final detail = activities.isEmpty
        ? '留下作品、选择风格后，判断会慢慢贴近你。'
        : '行动方式偏向${activities.take(2).join('、')}；推荐只在条件成立时出现。';
    return Material(
      color: V2Palette.night,
      borderRadius: BorderRadius.circular(36),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -34,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: V2Palette.moss.withValues(alpha: .22),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(27),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(CupertinoIcons.eye, color: V2Palette.moss, size: 20),
                    SizedBox(width: 9),
                    Text(
                      '栖光如何理解我',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  headline,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '${library?.savedNotes.length ?? 0} 张纸条 · '
                  '${library?.savedPlaces.length ?? 0} 个地点 · '
                  '${library?.sessionResults.length ?? 0} 次结果',
                  style: const TextStyle(
                    color: V2Palette.moss,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class V2ProfileSettingsPage extends StatelessWidget {
  const V2ProfileSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => _V2SecondaryPage(
    title: '设置',
    subtitle: '调整栖光的表达、隐私和设备行为。',
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        _V2SettingsEntry(
          icon: CupertinoIcons.slider_horizontal_3,
          title: '我的观看方式',
          detail: '题材、行动方式、器材和 AI 表达密度',
          onTap: () => context.push('/profile/style'),
        ),
        const SizedBox(height: 12),
        _V2SettingsEntry(
          icon: CupertinoIcons.lock_shield,
          title: '隐私与感受',
          detail: '动态、高对比、匿名反馈和本地活动清理',
          onTap: () => context.push('/profile/privacy'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          _V2SettingsEntry(
            icon: CupertinoIcons.lab_flask,
            title: '动态背景实验室',
            detail: '仅开发调试可见',
            onTap: () => context.push('/ambient-debug'),
          ),
        ],
      ],
    ),
  );
}

class _V2SettingsEntry extends StatelessWidget {
  const _V2SettingsEntry({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    color: V2Palette.paper,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, color: V2Palette.moss, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_right, color: V2Palette.mutedInk),
        ],
      ),
    ),
  );
}

class V2ProfileStylePage extends ConsumerStatefulWidget {
  const V2ProfileStylePage({super.key});

  @override
  ConsumerState<V2ProfileStylePage> createState() => _V2ProfileStylePageState();
}

class _V2ProfileStylePageState extends ConsumerState<V2ProfileStylePage> {
  late final TextEditingController _equipment;

  @override
  void initState() {
    super.initState();
    _equipment = TextEditingController(
      text: ref.read(profilePreferencesProvider).equipmentList,
    );
  }

  @override
  void dispose() {
    _equipment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(profilePreferencesProvider);
    final controller = ref.read(profilePreferencesProvider.notifier);
    return _V2SecondaryPage(
      title: '我的观看方式',
      subtitle: '这些偏好只改变表达与排序，不会把有限条件说成好机会。',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _V2PreferenceField(
            title: '常拍题材',
            options: const ['风光', '人文', '城市', '星空', '生态'],
            selected: value.photographyPreferences,
            onToggle: controller.togglePhotographyPreference,
          ),
          const SizedBox(height: 18),
          _V2PreferenceField(
            title: '行动方式',
            options: const ['自驾', '轻徒步', '重装徒步', '慢探索'],
            selected: value.activityPreferences,
            onToggle: controller.toggleActivityPreference,
          ),
          const SizedBox(height: 18),
          _V2SectionObject(
            title: '随身器材',
            child: TextField(
              controller: _equipment,
              minLines: 2,
              maxLines: 3,
              onChanged: controller.setEquipmentList,
              decoration: const InputDecoration(
                hintText: '例如：手机、相机、三脚架、广角镜头',
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _V2SectionObject(
            title: '表达密度',
            child: Row(
              children: [
                for (final tone in AiTone.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: V2Pressable(
                        onTap: () => controller.setAiTone(tone),
                        compact: true,
                        color: value.aiTone == tone
                            ? V2Palette.moss
                            : V2Palette.canvas,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            tone.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: value.aiTone == tone
                                  ? Colors.white
                                  : V2Palette.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class V2ProfileLibraryPage extends ConsumerWidget {
  const V2ProfileLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(userLibraryProvider);
    return _V2SecondaryPage(
      title: '我留下的',
      subtitle: '地点、纸条和拍摄结果都保存在本机。',
      child: library.when(
        loading: () => const V2LoadingObject(label: '正在读取本地内容'),
        error: (_, _) => const Center(child: Text('本地内容暂时不可读')),
        data: (value) => ListView(
          padding: EdgeInsets.zero,
          children: [
            _V2LibraryGroup(
              title: '灵感纸条',
              empty: '还没有收藏纸条',
              items: value.savedNotes
                  .take(8)
                  .map(
                    (item) => _V2LibraryItem(
                      title: item.displayLabel,
                      detail: item.detail,
                      onDelete: () => ref
                          .read(userLibraryProvider.notifier)
                          .deleteSavedNote(item.id),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            _V2LibraryGroup(
              title: '收藏地点',
              empty: '还没有收藏地点',
              items: value.savedPlaces
                  .take(8)
                  .map(
                    (item) =>
                        _V2LibraryItem(title: item.name, detail: item.category),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            _V2SectionObject(
              title: '拍摄记录',
              child: Text(
                '${value.sessionResults.length} 次结果 · '
                '${value.watchedSessions.length} 个关注窗口 · '
                '${value.offlinePhotographyPacks.length} 个离线包',
                style: const TextStyle(color: V2Palette.mutedInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class V2ProfilePrivacyPage extends ConsumerWidget {
  const V2ProfilePrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(profilePreferencesProvider);
    final controller = ref.read(profilePreferencesProvider.notifier);
    return _V2SecondaryPage(
      title: '隐私与感受',
      subtitle: '位置用于当前环境，个人偏好和收藏默认留在本机。',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _V2ToggleObject(
            title: '减少动态',
            detail: '关闭抬升、摇动和大幅位移，只保留必要状态变化。',
            value: value.reduceMotion,
            onTap: controller.toggleReduceMotion,
          ),
          const SizedBox(height: 12),
          _V2ToggleObject(
            title: '高对比度',
            detail: '提高文本和控制对象的视觉边界。',
            value: value.highContrast,
            onTap: controller.toggleHighContrast,
          ),
          const SizedBox(height: 12),
          _V2ToggleObject(
            title: '匿名拍摄反馈',
            detail: '仅上传规则结果与因素，不包含坐标、路线或照片。',
            value: value.shareAnonymousPhotographyFeedback,
            onTap: () => controller.setShareAnonymousPhotographyFeedback(
              !value.shareAnonymousPhotographyFeedback,
            ),
          ),
          const SizedBox(height: 18),
          const _V2SectionObject(
            title: '问栖光与模型服务',
            child: Text(
              '允许模型改写的问题只会发送问题正文、最多 8 轮对话和确定性模板答案给已配置的模型供应商。精确坐标、位置衍生地点、天气事实和野生动物资料不会进入普通模型提示。天气安全、风险和附近推荐保持本地或服务端确定性回答。助手联网搜索默认关闭；管理员开启后，搜索词会发送给已配置的审核来源搜索服务。',
              style: TextStyle(color: V2Palette.mutedInk, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          _V2SectionObject(
            title: '清理本地拍摄活动',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '删除关注窗口、拍摄结果和离线包，不影响收藏地点与纸条。',
                  style: TextStyle(color: V2Palette.mutedInk, height: 1.4),
                ),
                const SizedBox(height: 14),
                V2Pressable(
                  onTap: () => unawaited(
                    ref
                        .read(userLibraryProvider.notifier)
                        .clearPhotographyActivity(),
                  ),
                  compact: true,
                  color: V2Palette.dangerSoft,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Text(
                      '清理拍摄活动',
                      style: TextStyle(
                        color: V2Palette.danger,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _V2SecondaryPage extends StatelessWidget {
  const _V2SecondaryPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: V2Palette.canvas,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            V2BackButton(onTap: () => context.pop()),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 32,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class _V2PreferenceField extends StatelessWidget {
  const _V2PreferenceField({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });
  final String title;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => _V2SectionObject(
    title: title,
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          V2Pressable(
            onTap: () => onToggle(option),
            compact: true,
            color: selected.contains(option)
                ? V2Palette.moss
                : V2Palette.canvas,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Text(
                option,
                style: TextStyle(
                  color: selected.contains(option)
                      ? Colors.white
                      : V2Palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _V2SectionObject extends StatelessWidget {
  const _V2SectionObject({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: V2Palette.paper,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: V2Palette.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: V2Palette.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _V2LibraryGroup extends StatelessWidget {
  const _V2LibraryGroup({
    required this.title,
    required this.empty,
    required this.items,
  });
  final String title;
  final String empty;
  final List<_V2LibraryItem> items;

  @override
  Widget build(BuildContext context) => _V2SectionObject(
    title: title,
    child: items.isEmpty
        ? Text(empty, style: const TextStyle(color: V2Palette.mutedInk))
        : Column(children: items),
  );
}

class _V2LibraryItem extends StatelessWidget {
  const _V2LibraryItem({
    required this.title,
    required this.detail,
    this.onDelete,
  });
  final String title;
  final String detail;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: V2Palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: V2Palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(CupertinoIcons.trash, size: 18),
          ),
      ],
    ),
  );
}

class _V2ToggleObject extends StatelessWidget {
  const _V2ToggleObject({
    required this.title,
    required this.detail,
    required this.value,
    required this.onTap,
  });
  final String title;
  final String detail;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => V2Pressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 48,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? V2Palette.moss : V2Palette.line,
              borderRadius: BorderRadius.circular(99),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 22),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
