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
