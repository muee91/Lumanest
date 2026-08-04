from pathlib import Path

page_path = Path('lib/src/presentation_v2/explore/v2_explore_page.dart')
test_path = Path('test/presentation_v2/explore/v2_explore_theme_strip_test.dart')
catalog_path = Path('lib/src/features/explore/application/explore_intent_catalog.dart')

page = page_path.read_text()

old_call = """                child: _V2IntentStrip(
                  intent: intent,
                  regionThemes: regionThemes,
                  onSelect: _selectExploreIntent,
                  onSelectRegionTheme: _selectRegionTheme,
                  onOpenServices: () => unawaited(_openNearbyServices()),
                ),
"""
new_call = """                child: _V2IntentStrip(
                  intent: intent,
                  regionThemes: regionThemes,
                  onSelect: _selectExploreIntent,
                  onSelectRegionTheme: _selectRegionTheme,
                ),
"""
if old_call not in page:
    raise SystemExit('intent strip call anchor not found')
page = page.replace(old_call, new_call, 1)

method_start = page.find('  Future<void> _openNearbyServices() async {')
method_end = page.find('  void _searchCurrentMapArea() {', method_start)
if method_start == -1 or method_end == -1:
    raise SystemExit('nearby services folding method anchors not found')
page = page[:method_start] + page[method_end:]

class_start = page.find('class _V2IntentStrip extends StatelessWidget {')
class_end = page.find('class _V2ThemeChip extends StatelessWidget {', class_start)
if class_start == -1 or class_end == -1:
    raise SystemExit('intent strip class anchors not found')
new_class = """class _V2IntentStrip extends StatelessWidget {
  const _V2IntentStrip({
    required this.intent,
    required this.regionThemes,
    required this.onSelect,
    required this.onSelectRegionTheme,
  });

  final ExploreIntentState intent;
  final List<RegionPhotoTheme> regionThemes;
  final ValueChanged<ExploreCreativeIntent> onSelect;
  final ValueChanged<RegionPhotoTheme> onSelectRegionTheme;

  @override
  Widget build(BuildContext context) {
    final hasListedSelection = ExploreCreativeIntent.values.any(
      (item) => item.category == intent.category,
    );
    final hasContextSelection =
        intent.activeFocus != null ||
        (intent.regionTheme == null && !hasListedSelection);
    final chips = <Widget>[
      if (hasContextSelection)
        _V2ThemeChip(
          key: const Key('v2-explore-theme-context'),
          label: _categoryTitle(intent.category),
          category: intent.category,
          selected: true,
        ),
      for (final item in ExploreCreativeIntent.values)
        _V2ThemeChip(
          key: Key('v2-explore-theme-${item.name}'),
          label: item.label,
          category: item.category,
          selected:
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
page = page[:class_start] + new_class + page[class_end:]
page_path.write_text(page)

catalog = catalog_path.read_text()
old_comment = """/// Utility POIs are intentionally grouped behind one “附近服务” affordance.
/// They remain one tap away without competing with creative discovery themes.
"""
new_comment = """/// Utility POIs remain a separate semantic group, but every item is exposed
/// directly in Explore's single horizontally scrollable tab strip.
"""
if old_comment not in catalog:
    raise SystemExit('catalog comment anchor not found')
catalog_path.write_text(catalog.replace(old_comment, new_comment, 1))

test = test_path.read_text()
old_expectations = """      expect(
        find.byKey(const Key('v2-explore-nearby-services')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const Key('v2-explore-theme-food')),
        ),
        findsNothing,
      );
"""
new_expectations = """      expect(
        find.byKey(const Key('v2-explore-nearby-services')),
        findsNothing,
      );
      await tester.drag(strip, const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('v2-explore-theme-supplies')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('v2-explore-theme-parking')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('v2-explore-theme-food')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('v2-explore-theme-fuel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('v2-explore-theme-medical')),
        findsOneWidget,
      );
"""
if old_expectations not in test:
    raise SystemExit('theme strip expectation anchor not found')
test = test.replace(old_expectations, new_expectations, 1)

old_humanity_tap = """      await tester.tap(find.byKey(const Key('v2-explore-theme-humanity')));
      await tester.pump();

      expect(
        container.read(exploreIntentProvider).category,
        NearbyPlaceCategory.humanity,
      );

      await tester.tap(searchButton);
"""
new_humanity_tap = """      await tester.tap(find.byKey(const Key('v2-explore-theme-food')));
      await tester.pump();

      expect(
        container.read(exploreIntentProvider).category,
        NearbyPlaceCategory.food,
      );

      await tester.tap(searchButton);
"""
if old_humanity_tap not in test:
    raise SystemExit('theme strip tap anchor not found')
test_path.write_text(test.replace(old_humanity_tap, new_humanity_tap, 1))
