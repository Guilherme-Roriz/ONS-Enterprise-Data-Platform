from __future__ import annotations

import pytest

from ETL.config.database import get_database_url


pytestmark = pytest.mark.unit


def test_explicit_database_url_wins(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg2://explicit/db")
    monkeypatch.setenv("DB_HOST", "ignored")
    assert get_database_url() == "postgresql+psycopg2://explicit/db"


def test_database_url_uses_defaults(monkeypatch: pytest.MonkeyPatch) -> None:
    for key in ("DATABASE_URL", "DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"):
        monkeypatch.delenv(key, raising=False)
    assert get_database_url() == "postgresql+psycopg2://etl_user:@localhost:5432/ons_edp"


def test_database_url_escapes_password(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.setenv("DB_PORT", "55432")
    monkeypatch.setenv("DB_NAME", "warehouse")
    monkeypatch.setenv("DB_USER", "etl")
    monkeypatch.setenv("DB_PASSWORD", "p@ss/word")
    assert get_database_url() == (
        "postgresql+psycopg2://etl:p%40ss%2Fword@db.internal:55432/warehouse"
    )

