from __future__ import annotations

import random
from pathlib import Path

import pytest

from DDL import populate


pytestmark = pytest.mark.unit


class FakeCursor:
    def __init__(self, rows: list[tuple[int, str]]) -> None:
        self.rows = rows
        self.executed: tuple[str, tuple[list[str]]] | None = None

    def execute(self, sql: str, params: tuple[list[str]]) -> None:
        self.executed = (sql, params)

    def fetchall(self) -> list[tuple[int, str]]:
        return self.rows


def test_fetch_ids_returns_real_ids_in_business_key_order() -> None:
    cursor = FakeCursor([(900, "AC"), (42, "SP")])
    result = populate.fetch_ids(cursor, "state", "state_id", "state_code", ["SP", "AC"])
    assert result == [42, 900]
    assert cursor.executed is not None
    assert cursor.executed[1] == (["SP", "AC"],)


def test_reset_generators_replays_the_same_sequence() -> None:
    populate.reset_generators()
    first = [random.random() for _ in range(4)]
    first_name = populate.fake.company()
    populate.reset_generators()
    assert [random.random() for _ in range(4)] == first
    assert populate.fake.company() == first_name


def test_seed_source_contains_no_destructive_reset() -> None:
    source = Path(populate.__file__).read_text(encoding="utf-8").upper()
    for destructive in ("TRUNCATE ", "DROP SCHEMA", "DROP TABLE", "DELETE FROM"):
        assert destructive not in source


def test_seed_uses_a_fixed_scd2_effective_timestamp() -> None:
    assert populate.SEED_LAST_UPDATED.isoformat() == "2026-07-01T00:00:00"


def test_bulk_insert_uses_target_column_types_and_conflict_key(monkeypatch) -> None:
    captured = {}

    def fake_execute_values(cursor, sql, rows):
        captured.update(cursor=cursor, sql=sql, rows=rows)

    monkeypatch.setattr(populate.psycopg2.extras, "execute_values", fake_execute_values)
    marker = object()
    rows = [("substation", 1, None), ("transmission_line", 2, 10.5)]

    populate.insert_rows(
        marker,
        "measurement",
        ["asset_type", "asset_id", "power_flow_mw"],
        rows,
        ["asset_type", "asset_id"],
    )

    assert captured["cursor"] is marker
    assert captured["rows"] == rows
    assert "INSERT INTO measurement" in captured["sql"]
    assert "VALUES %s" in captured["sql"]
    assert "ON CONFLICT (asset_type, asset_id) DO NOTHING" in captured["sql"]
    assert "SELECT" not in captured["sql"]


def test_capacity_trigger_schema_qualifies_its_lookup() -> None:
    ddl = (Path(populate.__file__).parent / "oltp.sql").read_text(encoding="utf-8")
    assert "FROM oltp.plant" in ddl
