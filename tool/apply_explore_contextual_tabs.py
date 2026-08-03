from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"{label}: start marker not found")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError(f"{label}: end marker not found")
    return text[:start_index] + replacement + text[end_index:]


controller = """import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_photo_theme_focus.dart';

class ExploreIntentState {
  const ExploreIntentState({
    required this.category,
    this.activeFocus,
    this.creativeIntent,
    this.regionTheme,
    this.sceneCategory = NearbyPlaceCategory.viewpoint,
    this.followsScene = true,
  });

  final NearbyPlaceCategory category;
  final ExploreFocus? activeFocus;
  final ExploreCreativeIntent? creativeIntent;
  final RegionPhotoTheme? regionTheme;
  final NearbyPlaceCategory sceneCategory;
  final bool followsScene;

  bool get hasActiveIntent => activeFocus != null;
}

class ExploreIntentController extends Notifier<ExploreIntentState> {
  @override
  ExploreIntentState build() =>
      const ExploreIntentState(category: NearbyPlaceCategory.viewpoint);

  /// Activates a focus explicitly requested by a Today/Intelligence action.
  /// A plain Explore route preserves a manual category or regional theme,
  /// unless it is clearing an active temporary focus.
  void activate(ExploreFocus focus) {
    if (focus == ExploreFocus.photography) {
      if (!state.hasActiveIntent) return;
      state = ExploreIntentState(
        category: state.sceneCategory,
        sceneCategory: state.sceneCategory,
      );
      return;
    }
    state = ExploreIntentState(
      category: focus.category,
      activeFocus: focus,
      sceneCategory: state.sceneCategory,
    );
  }

  /// A user-picked category or a completed route/search action takes over from
  /// temporary intent without forcing the photography default.
  void complete({required NearbyPlaceCategory category}) {
    state = ExploreIntentState(
      category: category,
      sceneCategory: state.sceneCategory,
      followsScene: false,
    );
  }

  /// A local Explore choice. It only changes which existing nearby query is
  /// used; it does not claim that a photographic condition exists.
  void chooseCreativeIntent(ExploreCreativeIntent intent) {
    state = ExploreIntentState(
      category: intent.category,
      creativeIntent: intent,
      sceneCategory: state.sceneCategory,
      followsScene: false,
    );
  }

  /// Keeps the verified regional label while mapping it to the bounded nearby
  /// query vocabulary. The label is later forwarded to Discovery as search
  /// focus, so a theme such as “潮汐海塘” is not reduced to generic “水岸”.
  void chooseRegionTheme(RegionPhotoTheme theme) {
    state = ExploreIntentState(
      category: focusForRegionPhotoTheme(theme).category,
      regionTheme: theme,
      sceneCategory: state.sceneCategory,
      followsScene: false,
    );
  }

  /// Applies a deterministic default layer when the user has not manually
  /// selected a category and no temporary cross-page intent is active.
  void syncScene(SceneType scene) {
    final sceneCategory = switch (scene) {
      SceneType.lake => NearbyPlaceCategory.waterfront,
      SceneType.village => NearbyPlaceCategory.humanity,
      SceneType.city ||
      SceneType.mountain ||
      SceneType.desert ||
      SceneType.unknown => NearbyPlaceCategory.viewpoint,
    };
    if (sceneCategory == state.sceneCategory) return;
    state = ExploreIntentState(
      category: state.followsScene && !state.hasActiveIntent
          ? sceneCategory
          : state.category,
      activeFocus: state.activeFocus,
      creativeIntent: state.creativeIntent,
      regionTheme: state.regionTheme,
      sceneCategory: sceneCategory,
      followsScene: state.followsScene,
    );
  }

  /// Timeout restores the latest context-derived layer. Returns false when
  /// there was no temporary intent to expire.
  bool expire() {
    if (!state.hasActiveIntent) return false;
    state = ExploreIntentState(
      category: state.sceneCategory,
      sceneCategory: state.sceneCategory,
    );
    return true;
  }
}

final exploreIntentProvider =
    NotifierProvider<ExploreIntentController, ExploreIntentState>(
      ExploreIntentController.new,
    );
"""
write(
    "lib/src/features/explore/application/explore_intent_controller.dart",
    controller,
)

catalog = """import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';
import 'package:luma_nest/src/features/explore/domain/region_photo_theme_focus.dart';

/// Stable Explore vocabulary. These two controls never move with location,
/// which preserves spatial memory while regional themes remain contextual.
const exploreCoreIntents = <ExploreCreativeIntent>[
  ExploreCreativeIntent.viewpoint,
  ExploreCreativeIntent.humanity,
];

/// Utility POIs are intentionally grouped behind one “附近服务” affordance.
/// They remain one tap away without competing with creative discovery themes.
const exploreNearbyServiceIntents = <ExploreCreativeIntent>[
  ExploreCreativeIntent.supplies,
  ExploreCreativeIntent.parking,
  ExploreCreativeIntent.food,
  ExploreCreativeIntent.fuel,
  ExploreCreativeIntent.medical,
];

bool isExploreNearbyServiceIntent(ExploreCreativeIntent? intent) =>
    intent != null && exploreNearbyServiceIntents.contains(intent);

NearbyPlaceCategory categoryForExploreRegionTheme(RegionPhotoTheme theme) =>
    focusForRegionPhotoTheme(theme).category;

/// Shows at most two source-validated regional themes. Duplicate identifiers
/// or labels are collapsed deterministically so a noisy brief cannot expand
/// the navigation strip.
List<RegionPhotoTheme> selectExploreRegionThemes(
  Iterable<RegionPhotoTheme> themes, {
  int maxItems = 2,
}) {
  if (maxItems <= 0) return const <RegionPhotoTheme>[];
  final selected = <RegionPhotoTheme>[];
  final ids = <String>{};
  final labels = <String>{};
  for (final theme in themes) {
    final id = theme.id.trim();
    final label = theme.label.trim();
    if (id.isEmpty || label.isEmpty) continue;
    final normalizedLabel = label.toLowerCase();
    if (!ids.add(id) || !labels.add(normalizedLabel)) continue;
    selected.add(RegionPhotoTheme(id: id, label: label));
    if (selected.length == maxItems) break;
  }
  return List.unmodifiable(selected);
}
"""
write(
    "lib/src/features/explore/application/explore_intent_catalog.dart",
    catalog,
)

providers_path = "lib/src/features/explore/application/nearby_place_providers.dart"
providers = read(providers_path)
providers = replace_once(
    providers,
    "  final category = ref.watch(nearbyCategoryProvider);\n",
    "  final intent = ref.watch(exploreIntentProvider);\n"
    "  final category = intent.category;\n",
    "watch full explore intent",
)
providers = replace_once(
    providers,
    "    focus: _discoveryFocus(category, null),\n",
    "    focus: _discoveryFocus(category, intent.regionTheme?.label),\n",
    "forward regional theme to discovery",
)
old_focus = """String _discoveryFocus(NearbyPlaceCategory category, String? city) {
  final region = city?.trim().isNotEmpty == true ? city!.trim() : '当前位置';
  final subject = switch (category) {
    NearbyPlaceCategory.sunriseCandidate => '日出摄影地点',
    NearbyPlaceCategory.nightSkyCandidate => '夜空摄影地点',
    NearbyPlaceCategory.waterfront => '水岸公园和滨水景观地点',
    NearbyPlaceCategory.humanity => '人文街巷、传统建筑和文化空间',
    _ => '公开资料提及的观景地点',
  };
  return '$region及周边$subject';
}
"""
new_focus = """String _discoveryFocus(
  NearbyPlaceCategory category,
  String? regionalThemeLabel,
) {
  final theme = regionalThemeLabel?.trim();
  if (theme != null && theme.isNotEmpty) {
    return '当前位置及周边与$theme相关的地点、场景和拍摄线索';
  }
  final subject = switch (category) {
    NearbyPlaceCategory.sunriseCandidate => '日出摄影地点',
    NearbyPlaceCategory.nightSkyCandidate => '夜空摄影地点',
    NearbyPlaceCategory.waterfront => '水岸公园和滨水景观地点',
    NearbyPlaceCategory.humanity => '人文街巷、传统建筑和文化空间',
    _ => '公开资料提及的观景地点',
  };
  return '当前位置及周边$subject';
}
"""
providers = replace_once(
    providers,
    old_focus,
    new_focus,
    "regional discovery focus",
)
write(providers_path, providers)

page_path = "lib/src/presentation_v2/explore/v2_explore_page.dart"
page = read(page_path)
page = replace_once(
    page,
    "import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';\n",
    "import 'package:luma_nest/src/features/explore/application/explore_intent_catalog.dart';\n"
    "import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';\n",
    "explore catalog import",
)
page = replace_once(
    page,
    "    final intent = ref.watch(exploreIntentProvider);\n"
    "    final searchArea = ref.watch(nearbySearchAreaProvider);\n",
    "    final intent = ref.watch(exploreIntentProvider);\n"
    "    final regionThemes = selectExploreRegionThemes(\n"
    "      ref.watch(regionBriefControllerProvider).brief?.photoThemes ??\n"
    "          const <RegionPhotoTheme>[],\n"
    "    );\n"
    "    final searchArea = ref.watch(nearbySearchAreaProvider);\n",
    "derive regional themes",
)
page = replace_once(
    page,
    "                child: _V2IntentStrip(\n"
    "                  category: intent.category,\n"
    "                  onSelect: _selectExploreIntent,\n"
    "                ),\n",
    "                child: _V2IntentStrip(\n"
    "                  intent: intent,\n"
    "                  regionThemes: regionThemes,\n"
    "                  onSelect: _selectExploreIntent,\n"
    "                  onSelectRegionTheme: _selectRegionTheme,\n"
    "                  onOpenServices: () => unawaited(_openNearbyServices()),\n"
    "                ),\n",
    "contextual intent strip invocation",
)
method_anchor = """  void _searchCurrentMapArea() {
"""
new_methods = """  void _selectRegionTheme(RegionPhotoTheme theme) {
    _debounce?.cancel();
    _searchGeneration += 1;
    _searchController.clear();
    _searchFocus.unfocus();
    ref.read(exploreIntentProvider.notifier).chooseRegionTheme(theme);
    ref.read(nearbySearchAreaProvider.notifier).resetRadius();
    setState(() {
      _searchResults = null;
      _selectedPlace = null;
      _selectedSearchResult = null;
      _panelFraction = .5;
    });
  }

  Future<void> _openNearbyServices() async {
    final current = ref.read(exploreIntentProvider).creativeIntent;
    final selected = await showModalBottomSheet<ExploreCreativeIntent>(
      context: context,
      showDragHandle: true,
      backgroundColor: V2Palette.paper,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '附近服务',
                style: TextStyle(
                  color: V2Palette.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                '服务地点不会与创作主题混在同一层。',
                style: TextStyle(
                  color: V2Palette.mutedInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              for (final service in exploreNearbyServiceIntents)
                ListTile(
                  key: Key('v2-explore-service-${service.name}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    _intentIcon(service.category),
                    color: V2Palette.moss,
                  ),
                  title: Text(
                    service.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: current == service
                      ? const Icon(
                          CupertinoIcons.check_mark_circled_solid,
                          color: V2Palette.moss,
                        )
                      : const Icon(
                          CupertinoIcons.chevron_right,
                          color: V2Palette.mutedInk,
                          size: 17,
                        ),
                  onTap: () => Navigator.of(sheetContext).pop(service),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    _selectExploreIntent(selected);
  }

"""
page = replace_once(
    page,
    method_anchor,
    new_methods + method_anchor,
    "regional and service methods",
)
page = replace_once(
    page,
    """  static const _items = <(String, ExploreCreativeIntent)>[
    ('景点', ExploreCreativeIntent.viewpoint),
    ('美食', ExploreCreativeIntent.food),
    ('停车场', ExploreCreativeIntent.parking),
    ('加油站', ExploreCreativeIntent.fuel),
    ('拍摄补给', ExploreCreativeIntent.supplies),
    ('人文街巷', ExploreCreativeIntent.humanity),
  ];
""",
    """  static const _items = <(String, ExploreCreativeIntent)>[
    ('拍摄补给', ExploreCreativeIntent.supplies),
    ('停车场', ExploreCreativeIntent.parking),
    ('附近餐饮', ExploreCreativeIntent.food),
    ('加油站', ExploreCreativeIntent.fuel),
    ('附近医疗', ExploreCreativeIntent.medical),
  ];
""",
    "search shortcut service items",
)
page = replace_once(
    page,
    "              '附近候选',\n",
    "              '快捷服务',\n",
    "search shortcut title",
)
page = replace_once(
    page,
    "              '选择类别后查看当前位置附近结果',\n",
    "              '搜索具体地点，或直接查看当前位置附近服务',\n",
    "search shortcut detail",
)
new_strip = """class _V2IntentStrip extends StatelessWidget {
  const _V2IntentStrip({
    required this.intent,
    required this.regionThemes,
    required this.onSelect,
    required this.onSelectRegionTheme,
    required this.onOpenServices,
  });

  final ExploreIntentState intent;
  final List<RegionPhotoTheme> regionThemes;
  final ValueChanged<ExploreCreativeIntent> onSelect;
  final ValueChanged<RegionPhotoTheme> onSelectRegionTheme;
  final VoidCallback onOpenServices;

  @override
  Widget build(BuildContext context) {
    final serviceSelected = isExploreNearbyServiceIntent(
      intent.creativeIntent,
    );
    final hasContextSelection =
        intent.activeFocus != null ||
        (!serviceSelected &&
            intent.regionTheme == null &&
            !exploreCoreIntents.any(
              (item) => item.category == intent.category,
            ));
    final chips = <Widget>[
      if (hasContextSelection)
        _V2ThemeChip(
          key: const Key('v2-explore-theme-context'),
          label: _categoryTitle(intent.category),
          category: intent.category,
          selected: true,
        ),
      for (final item in exploreCoreIntents)
        _V2ThemeChip(
          key: Key('v2-explore-theme-${item.name}'),
          label: item.label,
          category: item.category,
          selected:
              !serviceSelected &&
              intent.activeFocus == null &&
              intent.regionTheme == null &&
              intent.category == item.category,
          onTap: () => onSelect(item),
        ),
      for (final theme in regionThemes)
        _V2ThemeChip(
          key: Key('v2-explore-region-theme-${theme.id}'),
          label: theme.label,
          category: categoryForExploreRegionTheme(theme),
          selected: intent.regionTheme?.id == theme.id,
          onTap: () => onSelectRegionTheme(theme),
        ),
      _V2ThemeChip(
        key: const Key('v2-explore-nearby-services'),
        label: '附近服务',
        category: serviceSelected
            ? intent.category
            : NearbyPlaceCategory.supply,
        selected: serviceSelected,
        onTap: onOpenServices,
      ),
    ];
    return SizedBox(
      key: const Key('v2-explore-theme-strip'),
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => chips[index],
      ),
    );
  }
}

"""
page = replace_between(
    page,
    "class _V2IntentStrip extends StatelessWidget {",
    "class _V2ThemeChip extends StatelessWidget {",
    new_strip,
    "replace explore intent strip",
)
write(page_path, page)

widget_test_path = "test/presentation_v2/explore/v2_explore_theme_strip_test.dart"
widget_test = read(widget_test_path)
widget_test = replace_once(
    widget_test,
    "      expect(find.byKey(const Key('v2-explore-theme-water')), findsOneWidget);\n",
    "      expect(\n"
    "        find.byKey(const Key('v2-explore-theme-context')),\n"
    "        findsOneWidget,\n"
    "      );\n"
    "      expect(\n"
    "        find.byKey(const Key('v2-explore-theme-viewpoint')),\n"
    "        findsOneWidget,\n"
    "      );\n"
    "      expect(\n"
    "        find.byKey(const Key('v2-explore-theme-humanity')),\n"
    "        findsOneWidget,\n"
    "      );\n"
    "      expect(\n"
    "        find.byKey(const Key('v2-explore-nearby-services')),\n"
    "        findsOneWidget,\n"
    "      );\n"
    "      expect(\n"
    "        find.descendant(\n"
    "          of: strip,\n"
    "          matching: find.byKey(const Key('v2-explore-theme-food')),\n"
    "        ),\n"
    "        findsNothing,\n"
    "      );\n",
    "theme strip expectations",
)
widget_test = replace_once(
    widget_test,
    "          of: find.byKey(const Key('v2-explore-theme-viewpoint')),\n",
    "          of: find.byKey(const Key('v2-explore-theme-context')),\n",
    "selected contextual chip",
)
widget_test = replace_once(
    widget_test,
    "      await tester.pump();\n      tester.view.viewInsets = const FakeViewPadding(bottom: 320);\n",
    "      await tester.pump();\n"
    "      expect(find.text('快捷服务'), findsOneWidget);\n"
    "      expect(find.text('景点'), findsNothing);\n"
    "      expect(find.text('人文街巷'), findsNothing);\n"
    "      expect(find.text('附近餐饮'), findsOneWidget);\n"
    "      tester.view.viewInsets = const FakeViewPadding(bottom: 320);\n",
    "search shortcut assertions",
)
write(widget_test_path, widget_test)

unit_test = """import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_catalog.dart';
import 'package:luma_nest/src/features/explore/application/explore_intent_controller.dart';
import 'package:luma_nest/src/features/explore/domain/nearby_place.dart';
import 'package:luma_nest/src/features/explore/domain/region_brief.dart';

void main() {
  test('explore keeps creative controls separate from nearby services', () {
    expect(
      exploreCoreIntents,
      const [
        ExploreCreativeIntent.viewpoint,
        ExploreCreativeIntent.humanity,
      ],
    );
    expect(
      exploreNearbyServiceIntents,
      const [
        ExploreCreativeIntent.supplies,
        ExploreCreativeIntent.parking,
        ExploreCreativeIntent.food,
        ExploreCreativeIntent.fuel,
        ExploreCreativeIntent.medical,
      ],
    );
    expect(isExploreNearbyServiceIntent(ExploreCreativeIntent.food), isTrue);
    expect(
      isExploreNearbyServiceIntent(ExploreCreativeIntent.humanity),
      isFalse,
    );
  });

  test('regional themes are deduplicated and capped', () {
    final selected = selectExploreRegionThemes(const [
      RegionPhotoTheme(id: 'tidal', label: '潮汐海塘'),
      RegionPhotoTheme(id: 'tidal-copy', label: '潮汐海塘'),
      RegionPhotoTheme(id: 'lantern', label: '硖石灯彩'),
      RegionPhotoTheme(id: 'celebrity', label: '名人故里'),
    ]);

    expect(selected.map((item) => item.id), ['tidal', 'lantern']);
  });

  test('regional theme keeps its label in intent state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const theme = RegionPhotoTheme(id: 'tidal', label: '潮汐海塘');

    container
        .read(exploreIntentProvider.notifier)
        .chooseRegionTheme(theme);

    final state = container.read(exploreIntentProvider);
    expect(state.regionTheme?.id, 'tidal');
    expect(state.regionTheme?.label, '潮汐海塘');
    expect(state.category, NearbyPlaceCategory.waterfront);

    container
        .read(exploreIntentProvider.notifier)
        .chooseCreativeIntent(ExploreCreativeIntent.parking);
    final serviceState = container.read(exploreIntentProvider);
    expect(serviceState.regionTheme, isNull);
    expect(serviceState.creativeIntent, ExploreCreativeIntent.parking);
  });
}
"""
write(
    "test/features/explore/explore_intent_catalog_test.dart",
    unit_test,
)

doc = """# Social signal ingestion references

This note records the GitHub projects reviewed for LumaNest social-data discovery.
It is an implementation reference, not permission to bypass platform controls.
Social content is a lead source only and never becomes a user-facing fact without
normal source admission and corroboration.

## Projects reviewed

### DIYgod/RSSHub

- Repository: https://github.com/DIYgod/RSSHub
- Useful pattern: isolated route adapters normalize heterogeneous websites into
  RSS/Atom; self-hosted instances, route health, caching and feed-level failure
  isolation fit the existing LumaNest feed worker.
- Constraint: AGPL-3.0. Do not copy route implementation into the proprietary
  service. Consume a separately deployed instance or independently implement a
  clean-room adapter against public/official interfaces.
- Decision: primary mechanism for reviewed public accounts and institution feeds.

### xpzouying/xiaohongshu-mcp

- Repository: https://github.com/xpzouying/xiaohongshu-mcp
- Useful pattern: browser-session gateway exposes login state, keyword search,
  feed listing, post details and user pages through HTTP/MCP; post detail uses
  identifiers returned by search/feed rather than guessing URLs.
- Operational reality: manual login, persisted browser cookies, xsec tokens and
  single-web-session constraints. The repository itself documents cookie expiry
  and account/session risks.
- License: Apache-2.0, but platform terms and account authorization remain
  separate constraints.
- Decision: do not run a shared LumaNest account. Support user-submitted links
  first; an optional isolated connector may use a dedicated, explicitly
  authorized session and must never enter the authoritative evidence tier.

### dataabc/weiboSpider

- Repository: https://github.com/dataabc/weiboSpider
- Useful pattern: incremental per-account collection, configurable date cursor,
  normalized post/user fields and multiple storage sinks.
- Operational reality: cookie-backed access for the main mode; it is optimized
  for known account IDs rather than geographic discovery.
- License: no top-level LICENSE file was found during review, so no source code
  should be copied.
- Decision: reproduce only the architecture: reviewed-account registry,
  per-account cursor, idempotent post keys and bounded incremental refresh.

### Evil0ctal/Douyin_TikTok_Download_API

- Repository: https://github.com/Evil0ctal/Douyin_TikTok_Download_API
- Useful pattern: asynchronous FastAPI facade, platform-specific crawler module,
  explicit upstream health/failure handling and normalized API responses.
- Operational reality: the project documents browser cookies and anti-bot
  signatures. Those techniques are brittle and unsuitable for a low-supervision
  production evidence chain.
- License: Apache-2.0.
- Decision: borrow the provider boundary and observability pattern only. Do not
  implement signature emulation or automated cookie acquisition in LumaNest.

### SocialSisterYi/bilibili-API-collect

- Repository: https://github.com/SocialSisterYi/bilibili-API-collect
- Status: archived, default branch marked deprecated.
- Useful pattern: endpoint taxonomy and field naming can inform normalization.
- Decision: no runtime dependency. Prefer RSSHub for reviewed UP accounts and
  official Bilibili/open-platform interfaces where authorization exists.

## LumaNest target architecture

```text
Reviewed account/feed registry
        |-- RSS/Atom/RSSHub provider
        |-- official API provider
        |-- optional isolated browser-session provider
        |-- user-submitted public link provider
                         |
                         v
                 social_signal_staging
                         |
        normalize, dedupe, expiry, geo/name hints
                         |
                         v
          official web / map / multi-source check
                         |
                         v
        existing Discovery evidence and admission
                         |
                         v
        Region Brief / candidate / no publication
```

## Provider contract

A future provider should return bounded public signals rather than UI cards:

```python
class SocialSignalProvider(Protocol):
    async def collect(self, request: SocialSignalRequest) -> list[SocialSignal]: ...
```

Minimum normalized fields:

- `platform`, `external_id`, `canonical_url`
- `author_id`, `author_name`, `account_policy_id`
- `published_at`, `observed_at`, `expires_at`
- bounded `title` and `text_excerpt`
- `place_names`, `region_hints`, optional public coordinates
- engagement snapshot as untrusted metadata, never a popularity claim
- `auth_mode`: public, official_oauth, user_session, or rss_proxy
- source license/terms policy and collection status

## Admission rules

1. Social engagement cannot produce “热门、人气、必去” facts.
2. A social post may trigger verification but cannot establish opening status,
   safety, route conditions or event time by itself.
3. Government, venue and organizer accounts can receive a higher source-policy
   tier, but account identity must be reviewed first.
4. Browser sessions are isolated per connector, encrypted at rest and disabled
   by default; no shared consumer account.
5. A provider failure never blocks Explore; it only removes that signal source.
6. Store excerpts and canonical links, not bulk media downloads or comments.

## Recommended implementation order

1. RSSHub reviewed-account adapter using the feed worker already in production.
2. Weibo reviewed-account incremental provider with public/official interfaces.
3. Bilibili reviewed-UP feed adapter.
4. User-submitted Xiaohongshu/Douyin link resolver.
5. Optional user-authorized browser connector only after policy and operations
   review; never use it for background regional crawling.
"""
write("docs/social-signal-ingestion-references.md", doc)

# The workflow and this script are one-shot scaffolding. Remove them before the
# branch commit so main receives only product code, tests and documentation.
(ROOT / ".github/workflows/apply-explore-contextual-tabs.yml").unlink()
Path(__file__).unlink()
