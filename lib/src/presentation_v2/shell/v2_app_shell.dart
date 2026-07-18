import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luma_nest/src/core/feedback/luma_nest_feedback_service.dart';
import 'package:luma_nest/src/design/luma_nest_motion.dart';
import 'package:luma_nest/src/design/luma_nest_theme.dart';
import 'package:luma_nest/src/features/profile/application/profile_preferences_controller.dart';
import 'package:luma_nest/src/presentation_v2/shared/v2_palette.dart';
import 'package:luma_nest/src/presentation_v2/shell/liquid_glass_nav.dart';

class V2AppShell extends ConsumerWidget {
  const V2AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = <_V2NavigationItem>[
    _V2NavigationItem('今日', CupertinoIcons.sun_max),
    _V2NavigationItem('探索', CupertinoIcons.compass),
    _V2NavigationItem('路线', CupertinoIcons.map),
    _V2NavigationItem('灵感', CupertinoIcons.sparkles),
    _V2NavigationItem('我的', CupertinoIcons.person_crop_circle),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => Theme(
    data: ref.watch(profilePreferencesProvider).highContrast
        ? LumaNestTheme.highContrastLight
        : LumaNestTheme.light,
    child: Scaffold(
      backgroundColor: V2Palette.canvas,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: LiquidGlassNav(
        borderRadius: V2Geometry.nav,
        height: 70,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Row(
          children: List.generate(_items.length, (index) {
            final selected = index == navigationShell.currentIndex;
            return Expanded(
              flex: selected ? 2 : 1,
              child: _V2NavigationButton(
                item: _items[index],
                selected: selected,
                onTap: () {
                  LumaNestFeedbackService.instance.play(
                    LumaNestSound.changeCard,
                    volume: .18,
                    haptic: LumaNestHaptic.selection,
                  );
                  navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  );
                },
              ),
            );
          }),
        ),
      ),
    ),
  );
}

class _V2NavigationItem {
  const _V2NavigationItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _V2NavigationButton extends StatefulWidget {
  const _V2NavigationButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _V2NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_V2NavigationButton> createState() => _V2NavigationButtonState();
}

class _V2NavigationButtonState extends State<_V2NavigationButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: widget.selected,
    button: true,
    label: widget.item.label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? .94 : 1,
        duration: _pressed ? LumaNestMotion.pressIn : LumaNestMotion.pressOut,
        child: AnimatedContainer(
          duration: LumaNestMotion.contentEnter,
          curve: LumaNestMotion.emphasized,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: widget.selected ? V2Palette.paper : Colors.transparent,
            borderRadius: BorderRadius.circular(21),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedRotation(
                turns: widget.selected ? 0 : -.04,
                duration: LumaNestMotion.contentEnter,
                child: Icon(
                  widget.item.icon,
                  color: widget.selected
                      ? V2Palette.ink
                      : Colors.white.withValues(alpha: .64),
                  size: widget.selected ? 21 : 22,
                ),
              ),
              Flexible(
                child: ClipRect(
                  child: AnimatedSize(
                    alignment: Alignment.centerLeft,
                    duration: LumaNestMotion.contentEnter,
                    curve: LumaNestMotion.emphasized,
                    child: widget.selected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 7),
                            child: Text(
                              widget.item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: V2Palette.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
