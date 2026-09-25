"""Binds the projection to the same contract the broker and the app parse.

`contract/context-v5.snapshot.golden.json` was captured from a running deployment,
and `contract/context-v5.policy.json` carries the numbers the three languages each
restate. Without this file a field added here passes FastAPI, fails the proxy's
exact-key gate, and shows up as an upstream outage.
"""

import json
from pathlib import Path

from annotated_types import MaxLen
from pydantic import ValidationError

from app import v5
from app.models import V5ContextEntry, V5SnapshotResponse

ROOT = Path(__file__).resolve().parents[3]
GOLDEN = json.loads((ROOT / "contract/context-v5.snapshot.golden.json").read_text())
POLICY = json.loads((ROOT / "contract/context-v5.policy.json").read_text())


def _max_length(model, field_name):
    metadata = model.model_fields[field_name].metadata
    return next((rule.max_length for rule in metadata if isinstance(rule, MaxLen)), None)


def test_golden_response_is_a_legal_v5_instance():
    parsed = V5SnapshotResponse.model_validate(GOLDEN)
    assert parsed.contract_version == POLICY["contractVersion"]
    assert len(parsed.entries) == len(GOLDEN["entries"])


def test_projection_emits_exactly_the_golden_top_level_keys():
    projected = V5SnapshotResponse.model_validate(GOLDEN).model_dump(by_alias=True)
    assert set(projected) == set(GOLDEN), (
        "the model can emit keys the shared contract does not carry"
    )


def test_openings_policy_matches_the_shared_contract():
    assert list(v5.BASE_SURFACES) == POLICY["baseSurfaces"]
    assert v5.INTERRUPT_LEAD_LIMIT.total_seconds() == POLICY["interruptLeadLimitSeconds"]
    safety = v5._allowed_surfaces(
        safety=True,
        interruptible=False,
        valid_from=v5.datetime(2026, 7, 14, 2, tzinfo=v5.timezone.utc),
        generated_at=v5.datetime(2026, 7, 14, 2, tzinfo=v5.timezone.utc),
    )
    assert sorted(set(safety) - set(POLICY["baseSurfaces"])) == sorted(
        POLICY["safetyExtraSurfaces"]
    )


def test_response_bounds_match_the_shared_contract():
    assert _max_length(V5SnapshotResponse, "entries") == POLICY["maxEntries"]
    assert _max_length(V5ContextEntry, "provenance") == POLICY["maxProvenance"]


def test_an_extra_field_is_rejected_here_too():
    widened = dict(GOLDEN, futureField=1)
    try:
        V5SnapshotResponse.model_validate(widened)
    except ValidationError:
        return
    raise AssertionError("extra='forbid' stopped enforcing the shared contract")
