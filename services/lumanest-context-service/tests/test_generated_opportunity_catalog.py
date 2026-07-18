from app.generated.opportunity_catalog import (
    CANONICAL_TAGS,
    CREATIVE_PROMPTS,
    OPPORTUNITY_CATALOG,
    OPPORTUNITY_CATALOG_VERSION,
    TIMING_POLICIES,
)


def test_generated_catalog_matches_engineering_spec_counts():
    assert OPPORTUNITY_CATALOG_VERSION == 1
    assert len(OPPORTUNITY_CATALOG) == 48
    assert sum(item["catalogTier"] == "core" for item in OPPORTUNITY_CATALOG) == 16
    assert sum(item["catalogTier"] == "legacyOnly" for item in OPPORTUNITY_CATALOG) == 3
    assert sum(item["catalogTier"] == "reserved" for item in OPPORTUNITY_CATALOG) == 29
    assert sum(item["coreCapability"] == "available" for item in OPPORTUNITY_CATALOG) == 6
    assert sum(item["coreCapability"] == "degraded" for item in OPPORTUNITY_CATALOG) == 7
    assert sum(item["coreCapability"] == "unavailable" for item in OPPORTUNITY_CATALOG) == 3
    assert len(TIMING_POLICIES) == 16
    assert len(CANONICAL_TAGS) == 96
    assert len(CREATIVE_PROMPTS) == 48


def test_all_core_timing_and_creative_tag_references_exist():
    timing_ids = {item["id"] for item in TIMING_POLICIES}
    tag_ids = {item["id"] for item in CANONICAL_TAGS}

    assert all(
        item["timingPolicy"] in timing_ids
        for item in OPPORTUNITY_CATALOG
        if item["catalogTier"] == "core"
    )
    assert all(
        set(item["techniqueTags"]) <= tag_ids
        and set(item["equipmentRequirement"]) <= tag_ids
        for item in CREATIVE_PROMPTS
    )
