#!/usr/bin/env python3
"""Validate LumaNest catalogs and generate Dart, Python, and MJS mirrors.

The four JSON documents in ``catalog/`` are the only hand-maintained catalog
facts. Generated files must never be edited directly. This script deliberately
uses only the Python standard library so it can run in CI before service
dependencies are installed.
"""

from __future__ import annotations

import argparse
import json
import pprint
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CATALOG_DIR = ROOT / "catalog"

SOURCE_PATHS = {
    "opportunities": CATALOG_DIR / "opportunities.v1.json",
    "timing": CATALOG_DIR / "timing-policies.v1.json",
    "tags": CATALOG_DIR / "tags.v1.json",
    "creative": CATALOG_DIR / "creative-prompts.v1.json",
}

OUTPUT_PATHS = {
    "dart": ROOT / "lib/src/generated/opportunity_catalog.g.dart",
    "python": (
        ROOT
        / "services/lumanest-context-service/app/generated/opportunity_catalog.py"
    ),
    "mjs": (
        ROOT
        / "services/lumanest-data-broker/src/generated/opportunity-catalog.mjs"
    ),
}

PRIMARY_SCENES = {
    "unknown",
    "urban",
    "village",
    "mountain",
    "plateau",
    "desert",
    "forest",
    "inlandWater",
    "coast",
    "wetland",
}
SCENE_FACETS = {
    "lake",
    "river",
    "reservoir",
    "wetland",
    "coast",
    "tidalFlat",
    "waterfall",
    "snowCover",
    "glacier",
    "canyon",
    "dune",
    "grassland",
    "forest",
    "bambooForest",
    "skyline",
    "architecture",
    "oldTown",
    "villageStreet",
    "openRoad",
    "openHorizon",
    "darkSky",
    "reviewedPeak",
    "reviewedViewpoint",
    "reflectiveSurface",
}
EVIDENCE_KINDS = {
    "light",
    "weather",
    "precipitation",
    "wind",
    "visibility",
    "astronomy",
    "authority",
    "place",
    "route",
    "equipment",
    "cloudLayers",
    "directionalRain",
    "humidityDewPoint",
    "moonTrajectory",
    "terrain",
    "lineOfSight",
    "legalStop",
    "tide",
    "lightPollution",
    "snowCover",
    "ecology",
}
CONTEXT_ACTIONS = {
    "openShootingWindow",
    "openExplore",
    "openRoute",
    "openPlaceDetail",
    "openAstronomyDetail",
    "openWildlifeDetail",
    "openSafetyDetail",
    "openCreativeDetail",
    "dismiss",
}
PREFERENCE_IDS = {
    "mountainLandform",
    "waterCoast",
    "cityArchitecture",
    "humanityStreet",
    "astroCelestial",
    "wildlifeEcology",
    "forestDetail",
    "aerialSpatial",
}
SAFETY_CONFLICT_IDS = {
    "thunderstorm",
    "strong-wind",
    "heavy-rain",
    "low-visibility",
    "road-stop-unsafe",
    "trail-return-risk",
    "official-closure",
    "wildlife-safety",
    "dust-hazard",
    "flash-flood",
    "unsafe-solar-viewing",
    "no-fly-zone",
}
TAG_CATEGORY_COUNTS = {
    "subject": 12,
    "scene": 12,
    "phenomenon": 16,
    "light": 12,
    "time": 8,
    "technique": 15,
    "activity": 8,
    "equipment": 13,
}


class CatalogError(ValueError):
    """A deterministic, user-actionable catalog validation failure."""


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CatalogError(f"{path.relative_to(ROOT)}: {error}") from error
    if not isinstance(value, dict):
        raise CatalogError(f"{path.relative_to(ROOT)}: root must be an object")
    return value


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CatalogError(message)


def _unique_ids(items: list[dict[str, Any]], label: str) -> set[str]:
    ids = [item.get("id") for item in items]
    _require(all(isinstance(value, str) and value for value in ids), f"{label}: every item needs an id")
    _require(len(ids) == len(set(ids)), f"{label}: duplicate ids")
    return set(ids)


def _string_list(item: dict[str, Any], key: str, label: str) -> list[str]:
    value = item.get(key)
    _require(isinstance(value, list), f"{label}.{key}: expected array")
    _require(all(isinstance(entry, str) and entry for entry in value), f"{label}.{key}: expected non-empty strings")
    _require(len(value) == len(set(value)), f"{label}.{key}: duplicate values")
    return value


def _validate_opportunities(
    document: dict[str, Any], timing_ids: set[str]
) -> list[dict[str, Any]]:
    _require(document.get("schemaVersion") == 1, "opportunities: schemaVersion must be 1")
    _require(document.get("catalogVersion") == 1, "opportunities: catalogVersion must be 1")
    items = document.get("items")
    _require(isinstance(items, list) and len(items) == 48, "opportunities: expected exactly 48 items")
    opportunity_ids = _unique_ids(items, "opportunities")

    for item in items:
        label = f"opportunities[{item['id']}]"
        tier = item.get("catalogTier")
        capability = item.get("coreCapability")
        _require(tier in {"core", "legacyOnly", "reserved"}, f"{label}: invalid catalogTier")
        if tier == "core":
            _require(capability in {"available", "degraded", "unavailable"}, f"{label}: invalid coreCapability")
            _require(item.get("timingPolicy") in timing_ids, f"{label}: unknown timingPolicy")
            confidence = item.get("minimumConfidence")
            _require(isinstance(confidence, (int, float)) and 0 <= confidence <= 1, f"{label}: invalid minimumConfidence")
        else:
            _require(capability is None, f"{label}: only core items have a capability")
            _require(item.get("timingPolicy") is None, f"{label}: inactive item must not activate timing")
            _require(item.get("minimumConfidence") is None, f"{label}: inactive item must not activate confidence")

        _require(item.get("modelType") in {"shootingSession", "factualEvent"}, f"{label}: invalid modelType")
        _require(item.get("family") in {"water", "mountain", "city", "landform", "atmosphere", "astronomy", "ecology", "humanityRoute"}, f"{label}: invalid family")
        presentation = item.get("presentation", {}).get("zhCN")
        _require(isinstance(presentation, dict), f"{label}: missing zhCN presentation")
        for key in ("name", "shortLabel", "emoji"):
            _require(isinstance(presentation.get(key), str) and presentation[key], f"{label}: missing presentation.{key}")
        if tier == "core":
            _require(isinstance(presentation.get("fallbackSummary"), str) and presentation["fallbackSummary"], f"{label}: core item needs fallbackSummary")

        scenes = set(_string_list(item, "primaryScenes", label))
        facets = set(_string_list(item, "sceneFacets", label))
        required = set(_string_list(item, "requiredEvidence", label))
        optional = set(_string_list(item, "optionalEvidence", label))
        suppresses = set(_string_list(item, "suppresses", label))
        conflicts = set(_string_list(item, "safetyConflicts", label))
        preferences = set(_string_list(item, "preferenceAffinities", label))
        _require(scenes <= PRIMARY_SCENES - {"unknown"}, f"{label}: unknown primary scene {sorted(scenes - PRIMARY_SCENES)}")
        _require(facets <= SCENE_FACETS, f"{label}: unknown scene facet {sorted(facets - SCENE_FACETS)}")
        _require(required <= EVIDENCE_KINDS, f"{label}: unknown required evidence {sorted(required - EVIDENCE_KINDS)}")
        _require(optional <= EVIDENCE_KINDS, f"{label}: unknown optional evidence {sorted(optional - EVIDENCE_KINDS)}")
        _require(required.isdisjoint(optional), f"{label}: evidence cannot be both required and optional")
        _require(suppresses <= opportunity_ids, f"{label}: unknown suppression target {sorted(suppresses - opportunity_ids)}")
        _require(conflicts <= SAFETY_CONFLICT_IDS, f"{label}: unknown safety conflict {sorted(conflicts - SAFETY_CONFLICT_IDS)}")
        _require(preferences <= PREFERENCE_IDS, f"{label}: unknown preference {sorted(preferences - PREFERENCE_IDS)}")
        _require(item.get("primaryAction") in CONTEXT_ACTIONS, f"{label}: invalid primaryAction")
        _require(item.get("fallbackAction") in CONTEXT_ACTIONS, f"{label}: invalid fallbackAction")

    tier_counts = {tier: sum(item["catalogTier"] == tier for item in items) for tier in ("core", "legacyOnly", "reserved")}
    _require(tier_counts == {"core": 16, "legacyOnly": 3, "reserved": 29}, f"opportunities: wrong tier counts {tier_counts}")
    capability_counts = {state: sum(item["coreCapability"] == state for item in items) for state in ("available", "degraded", "unavailable")}
    _require(capability_counts == {"available": 6, "degraded": 7, "unavailable": 3}, f"opportunities: wrong core capability counts {capability_counts}")
    return items


def _validate_timing(document: dict[str, Any]) -> tuple[list[dict[str, Any]], set[str]]:
    _require(document.get("schemaVersion") == 1, "timing: schemaVersion must be 1")
    items = document.get("items")
    _require(isinstance(items, list) and len(items) == 16, "timing: expected exactly 16 policies")
    timing_ids = _unique_ids(items, "timing")
    for item in items:
        label = f"timing[{item['id']}]"
        _require(re.fullmatch(r"timing\.[A-Za-z]+", item["id"]) is not None, f"{label}: invalid id")
        for key in ("catalogSpan", "actionableSpan", "advanceNotice", "farRefresh", "nearRefresh", "watchRefresh", "evidenceTtl", "windowRule"):
            _require(isinstance(item.get(key), str) and item[key], f"{label}: missing {key}")
        _require(re.fullmatch(r"\d+m", item["evidenceTtl"]) is not None, f"{label}: evidenceTtl must be minutes")
    return items, timing_ids


def _validate_tags(document: dict[str, Any]) -> tuple[list[dict[str, Any]], set[str]]:
    _require(document.get("schemaVersion") == 1, "tags: schemaVersion must be 1")
    items = document.get("items")
    _require(isinstance(items, list) and len(items) == 96, "tags: expected exactly 96 tags")
    tag_ids = _unique_ids(items, "tags")
    counts = {category: sum(item.get("category") == category for item in items) for category in TAG_CATEGORY_COUNTS}
    _require(counts == TAG_CATEGORY_COUNTS, f"tags: wrong category counts {counts}")
    _require(all(re.fullmatch(r"[a-z][a-z0-9_]*", item["id"]) for item in items), "tags: invalid id")
    return items, tag_ids


def _validate_creative(
    document: dict[str, Any], tag_ids: set[str]
) -> list[dict[str, Any]]:
    _require(document.get("schemaVersion") == 1, "creative: schemaVersion must be 1")
    items = document.get("items")
    _require(isinstance(items, list) and len(items) == 48, "creative: expected exactly 48 prompts")
    _unique_ids(items, "creative")
    for item in items:
        label = f"creative[{item['id']}]"
        _require(re.fullmatch(r"creative\.[a-z0-9_.]+", item["id"]) is not None, f"{label}: invalid id")
        _require(isinstance(item.get("shortLabel"), str) and item["shortLabel"], f"{label}: missing shortLabel")
        _require(isinstance(item.get("guide"), str) and item["guide"], f"{label}: missing guide")
        affinities = set(_string_list(item, "sceneAffinity", label))
        technique = set(_string_list(item, "techniqueTags", label))
        equipment = set(_string_list(item, "equipmentRequirement", label))
        _require(affinities <= PRIMARY_SCENES | {"all"}, f"{label}: unknown scene affinity {sorted(affinities - PRIMARY_SCENES - {'all'})}")
        _require(technique <= tag_ids, f"{label}: unknown technique tags {sorted(technique - tag_ids)}")
        _require(equipment <= tag_ids, f"{label}: unknown equipment tags {sorted(equipment - tag_ids)}")
        cooldown = item.get("cooldownHours")
        _require(isinstance(cooldown, int) and cooldown > 0, f"{label}: invalid cooldownHours")
    return items


def _dart_source(documents: dict[str, dict[str, Any]]) -> str:
    opportunity = documents["opportunities"]
    def encoded(value: Any) -> str:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))

    return "\n".join(
        [
            "// GENERATED CODE - DO NOT MODIFY BY HAND.",
            "// Run: python3 tool/generate_catalog.py",
            "",
            f"const int opportunityCatalogVersion = {opportunity['catalogVersion']};",
            "const String generatedOpportunityCatalogJson =",
            f"    r'''{encoded(opportunity['items'])}''';",
            "const String generatedTimingPoliciesJson =",
            f"    r'''{encoded(documents['timing']['items'])}''';",
            "const String generatedCanonicalTagsJson =",
            f"    r'''{encoded(documents['tags']['items'])}''';",
            "const String generatedCreativePromptsJson =",
            f"    r'''{encoded(documents['creative']['items'])}''';",
            "",
        ]
    )


def _python_source(documents: dict[str, dict[str, Any]]) -> str:
    opportunity = documents["opportunities"]
    values = {
        "OPPORTUNITY_CATALOG_VERSION": opportunity["catalogVersion"],
        "OPPORTUNITY_CATALOG": opportunity["items"],
        "TIMING_POLICIES": documents["timing"]["items"],
        "CANONICAL_TAGS": documents["tags"]["items"],
        "CREATIVE_PROMPTS": documents["creative"]["items"],
    }
    lines = [
        '"""Generated LumaNest catalogs. Do not edit by hand."""',
        "",
    ]
    for name, value in values.items():
        lines.append(f"{name} = {pprint.pformat(value, width=100, sort_dicts=False)}")
        lines.append("")
    return "\n".join(lines)


def _mjs_source(documents: dict[str, dict[str, Any]]) -> str:
    opportunity = documents["opportunities"]
    values = {
        "opportunityCatalogVersion": opportunity["catalogVersion"],
        "opportunityCatalog": opportunity["items"],
        "timingPolicies": documents["timing"]["items"],
        "canonicalTags": documents["tags"]["items"],
        "creativePrompts": documents["creative"]["items"],
    }
    lines = [
        "// GENERATED CODE - DO NOT MODIFY BY HAND.",
        "// Run: python3 tool/generate_catalog.py",
        "",
        "function deepFreeze(value) {",
        "  if (value && typeof value === 'object') {",
        "    Object.freeze(value);",
        "    for (const child of Object.values(value)) deepFreeze(child);",
        "  }",
        "  return value;",
        "}",
        "",
    ]
    for name, value in values.items():
        encoded = json.dumps(value, ensure_ascii=False, indent=2)
        if isinstance(value, int):
            lines.append(f"export const {name} = {encoded};")
        else:
            lines.append(f"export const {name} = deepFreeze({encoded});")
        lines.append("")
    return "\n".join(lines)


def _expected_outputs(documents: dict[str, dict[str, Any]]) -> dict[str, str]:
    return {
        "dart": _dart_source(documents),
        "python": _python_source(documents),
        "mjs": _mjs_source(documents),
    }


def _write_or_check(outputs: dict[str, str], check: bool) -> None:
    stale: list[str] = []
    for name, expected in outputs.items():
        path = OUTPUT_PATHS[name]
        if check:
            try:
                actual = path.read_text(encoding="utf-8")
            except OSError:
                actual = ""
            if actual != expected:
                stale.append(str(path.relative_to(ROOT)))
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding="utf-8")
    if stale:
        raise CatalogError(
            "generated catalog output is stale: "
            + ", ".join(stale)
            + "; run python3 tool/generate_catalog.py"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate sources and fail when generated files differ",
    )
    args = parser.parse_args()
    try:
        documents = {name: _load(path) for name, path in SOURCE_PATHS.items()}
        timing_items, timing_ids = _validate_timing(documents["timing"])
        tag_items, tag_ids = _validate_tags(documents["tags"])
        opportunity_items = _validate_opportunities(
            documents["opportunities"], timing_ids
        )
        creative_items = _validate_creative(documents["creative"], tag_ids)
        _write_or_check(_expected_outputs(documents), args.check)
    except CatalogError as error:
        print(f"catalog validation failed: {error}", file=sys.stderr)
        return 1

    print(
        "catalog ok: "
        f"opportunities={len(opportunity_items)} "
        f"timing={len(timing_items)} tags={len(tag_items)} "
        f"creative={len(creative_items)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
