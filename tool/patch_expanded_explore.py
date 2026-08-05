from pathlib import Path

path = Path('lib/src/presentation_v2/explore/v2_explore_page.dart')
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one match, got {count}: {old[:80]!r}')
    text = text.replace(old, new, 1)


replace_once(
    "import 'package:luma_nest/src/presentation_v2/explore/v2_provider_facts_sheet.dart';\n",
    "import 'package:luma_nest/src/presentation_v2/explore/v2_provider_facts_sheet.dart';\n"
    "import 'package:luma_nest/src/presentation_v2/explore/v2_region_brief_expansion.dart';\n",
)
replace_once(
    "      return _V2ExploreBrief(\n        brief: briefState.brief!,\n",
    "      return _V2ExploreBrief(\n        brief: briefState.brief!,\n        state: briefState,\n",
)
replace_once(
    "  const _V2ExploreBrief({\n    required this.brief,\n",
    "  const _V2ExploreBrief({\n    required this.brief,\n    required this.state,\n",
)
replace_once(
    "  final RegionBrief brief;\n  final ProviderFactsBundle? providerFacts;\n",
    "  final RegionBrief brief;\n  final RegionBriefState state;\n  final ProviderFactsBundle? providerFacts;\n",
)
replace_once(
    "                const Text(\n                  '正在更新区域资料',\n                  style: TextStyle(color: V2Palette.mutedInk, fontSize: 12),\n                ),\n",
    "                Text(\n                  state.isExpanding ? '正在扩展区域资料' : '正在更新区域资料',\n                  style: const TextStyle(\n                    color: V2Palette.mutedInk,\n                    fontSize: 12,\n                  ),\n                ),\n",
)

provider_anchor = "              if (providerSignals.isNotEmpty) ...["
theme_anchor = text.index("_V2BriefThemeCard(")
provider_index = text.index(provider_anchor, theme_anchor)
expansion = (
    "              const SizedBox(height: 14),\n"
    "              V2RegionBriefExpansionCard(\n"
    "                brief: brief,\n"
    "                state: state,\n"
    "                onExpand: onRefresh,\n"
    "              ),\n"
)
text = text[:provider_index] + expansion + text[provider_index:]

old_sections = """              if (sections.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text(
                  '值得了解',
                  style: TextStyle(
                    color: V2Palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...sections.map((item) => _V2BriefInsightCard(insight: item)),
              ],
"""
new_sections = """              if (sections.isNotEmpty) ...[
                const SizedBox(height: 22),
                V2RegionBriefInsightSections(insights: sections),
              ],
"""
replace_once(old_sections, new_sections)

private_start = text.index('class _V2BriefInsightCard extends StatelessWidget')
map_start = text.index(
    'class _V2ExploreMap extends ConsumerStatefulWidget',
    private_start,
)
text = text[:private_start] + text[map_start:]
path.write_text(text)
