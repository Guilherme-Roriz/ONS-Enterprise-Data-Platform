from __future__ import annotations

from pathlib import Path

import pytest

from ETL.data_vault.core import engine as vault_engine
from ETL.galaxy.core import engine as galaxy_engine


pytestmark = pytest.mark.unit


def write_mapping(root: Path, name: str, content: str) -> tuple[Path, Path]:
    mappings = root / "mappings"
    sql = root / "sql"
    mappings.mkdir(exist_ok=True)
    sql.mkdir(exist_ok=True)
    (mappings / name).write_text(content, encoding="utf-8")
    return mappings, sql


def test_data_vault_mappings_cover_every_source_and_target() -> None:
    steps = vault_engine.discover_steps()
    assert len(steps) == 13
    assert [step.order for step in steps] == sorted(step.order for step in steps)
    assert steps[0].name == "state"
    assert steps[-1].name == "asset_status"
    assert len({step.source for step in steps}) == 13
    assert len({target for step in steps for target in step.targets}) == 34


def test_galaxy_mappings_are_complete_and_ordered() -> None:
    steps = galaxy_engine.discover_steps()
    assert len(steps) == 14
    assert [step.order for step in steps] == sorted(step.order for step in steps)
    assert steps[0].name == "dim_date"
    assert steps[-1].name == "fact_asset_status"
    assert len({step.target for step in steps}) == 14


@pytest.mark.parametrize(
    ("discover", "mapping"),
    [
        (
            vault_engine.discover_steps,
            "pipeline: bad\norder: 1\nsource: oltp.source\n"
            "targets: [data_vault.target]\nsql_file: ../outside.sql\n",
        ),
        (
            galaxy_engine.discover_steps,
            "pipeline: bad\norder: 1\nsource: data_vault.source\n"
            "target: galaxy.target\nsql_file: ../outside.sql\n",
        ),
    ],
)
def test_mapping_rejects_sql_path_escape(tmp_path: Path, discover, mapping: str) -> None:
    mappings, sql = write_mapping(tmp_path, "bad.yaml", mapping)
    (tmp_path / "outside.sql").write_text("SELECT 1", encoding="utf-8")
    with pytest.raises(ValueError, match="Invalid SQL file"):
        discover(mappings, sql)


def test_vault_mapping_rejects_unsafe_source_identifier(tmp_path: Path) -> None:
    mappings, sql = write_mapping(
        tmp_path,
        "bad.yaml",
        "pipeline: bad\norder: 1\nsource: 'oltp.state; DROP TABLE oltp.state'\n"
        "targets: [data_vault.hub_state]\nsql_file: step.sql\n",
    )
    (sql / "step.sql").write_text("SELECT 0", encoding="utf-8")
    with pytest.raises(ValueError, match="Unsafe source identifier"):
        vault_engine.discover_steps(mappings, sql)


@pytest.mark.parametrize("discover", [vault_engine.discover_steps, galaxy_engine.discover_steps])
def test_mapping_directory_must_not_be_empty(tmp_path: Path, discover) -> None:
    mappings = tmp_path / "mappings"
    sql = tmp_path / "sql"
    mappings.mkdir()
    sql.mkdir()
    with pytest.raises(RuntimeError, match="No .* mappings found"):
        discover(mappings, sql)


def test_galaxy_rejects_duplicate_order(tmp_path: Path) -> None:
    mappings = tmp_path / "mappings"
    sql = tmp_path / "sql"
    mappings.mkdir()
    sql.mkdir()
    (sql / "one.sql").write_text("SELECT 1", encoding="utf-8")
    (sql / "two.sql").write_text("SELECT 2", encoding="utf-8")
    for name, sql_file in (("one", "one.sql"), ("two", "two.sql")):
        (mappings / f"{name}.yaml").write_text(
            f"pipeline: {name}\norder: 10\nsource: data_vault.source\n"
            f"target: galaxy.{name}\nsql_file: {sql_file}\n",
            encoding="utf-8",
        )
    with pytest.raises(ValueError, match="order values must be unique"):
        galaxy_engine.discover_steps(mappings, sql)


def test_etl_stages_share_control_infrastructure() -> None:
    assert vault_engine.ETLControl.__module__ == "ETL.common.control"
    assert galaxy_engine.ETLControl.__module__ == "ETL.common.control"
    assert vault_engine.DEFAULT_MAPPINGS_DIR.parent.name == "data_vault"
    assert galaxy_engine.DEFAULT_MAPPINGS_DIR.parent.name == "galaxy"

