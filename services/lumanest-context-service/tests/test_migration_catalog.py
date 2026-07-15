from datetime import datetime
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path


def _catalog_module():
    path = (
        Path(__file__).parents[1]
        / "alembic"
        / "versions"
        / "0004_nasa_meteor_catalog_2026.py"
    )
    spec = spec_from_file_location("nasa_meteor_catalog_2026", path)
    assert spec is not None and spec.loader is not None
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_catalog_uses_timezone_aware_datetimes_for_asyncpg_bindings():
    catalog = _catalog_module()

    values = [catalog.reviewed_at]
    for _, starts_at, ends_at, _, _ in catalog.events:
        values.extend((starts_at, ends_at))

    assert all(isinstance(value, datetime) for value in values)
    assert all(value.tzinfo is not None for value in values)
