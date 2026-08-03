from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "services/lumanest-data-broker/src/assistant/context-envelope.mjs"
TEST = ROOT / "services/lumanest-data-broker/test/assistant-context-envelope.test.mjs"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected one match in {path}, found {count}")
    path.write_text(text.replace(old, new), encoding="utf-8")


replace_once(
    MODULE,
    "function current(value, now) {\n"
    "  return validDate(value?.observedAt) && validDate(value?.expiresAt) &&\n"
    "    Date.parse(value.observedAt) <= now.getTime() + 5 * 60_000 &&\n"
    "    Date.parse(value.expiresAt) > now.getTime();\n"
    "}\n",
    "function current(value, now) {\n"
    "  return validDate(value?.observedAt) && validDate(value?.expiresAt) &&\n"
    "    Date.parse(value.observedAt) <= now.getTime() + 5 * 60_000 &&\n"
    "    Date.parse(value.expiresAt) > now.getTime();\n"
    "}\n\n"
    "function currentGenerated(value, now) {\n"
    "  return validDate(value?.generatedAt) && validDate(value?.expiresAt) &&\n"
    "    Date.parse(value.generatedAt) <= now.getTime() + 5 * 60_000 &&\n"
    "    Date.parse(value.expiresAt) > now.getTime();\n"
    "}\n",
)
replace_once(
    MODULE,
    "  if (!object(body) || !current(body, now) ||\n",
    "  if (!object(body) || !currentGenerated(body, now) ||\n",
)
replace_once(
    MODULE,
    "  if (!object(bundle) || !current(bundle, now)) {\n",
    "  if (!object(bundle) || !currentGenerated(bundle, now)) {\n",
)
replace_once(
    MODULE,
    "  const times = values.filter(validDate).map(Date.parse).filter((value) => value > now.getTime());\n",
    "  const times = values.filter(validDate).map((value) => Date.parse(value))\n"
    "    .filter((value) => value > now.getTime());\n",
)
replace_once(
    MODULE,
    "  const providerTask = providerFactsService?.facts({\n",
    "  const providerTask = providerFactsService == null\n"
    "    ? null\n"
    "    : Promise.resolve().then(() => providerFactsService.facts({\n",
)
replace_once(
    MODULE,
    "    providerIds,\n  });\n  const regionTask = typeof loadRegionBrief === 'function'\n",
    "    providerIds,\n  }));\n  const regionTask = typeof loadRegionBrief === 'function'\n",
)
replace_once(
    MODULE,
    "    ? loadRegionBrief({\n",
    "    ? Promise.resolve().then(() => loadRegionBrief({\n",
)
replace_once(
    MODULE,
    "        requestedSections: regionBriefSections,\n      })\n    : null;\n",
    "        requestedSections: regionBriefSections,\n      }))\n    : null;\n",
)
replace_once(
    MODULE,
    "  const contextFacts = [...baseLines, ...region.lines, ...providers.lines]\n"
    "    .map((line) => boundedText(line, 420))\n"
    "    .filter(Boolean)\n"
    "    .join('；')\n"
    "    .slice(0, 3_600);\n",
    "  const contextFacts = [...baseLines, ...region.lines, ...providers.lines]\n"
    "    .map((line) => boundedText(line, 420))\n"
    "    .filter(Boolean)\n"
    "    .join('；');\n"
    "  const boundedFacts = [...contextFacts].slice(0, 3_600).join('');\n",
)
replace_once(
    MODULE,
    "    contextFacts,\n    sources: Object.freeze(uniqueSources",
    "    contextFacts: boundedFacts,\n    sources: Object.freeze(uniqueSources",
)
replace_once(
    TEST,
    "          observedAt: '2026-08-03T11:50:00Z',\n"
    "          generatedAt: '2026-08-03T11:50:00Z',\n",
    "          generatedAt: '2026-08-03T11:50:00Z',\n",
)

print("assistant context freshness fixes applied")
