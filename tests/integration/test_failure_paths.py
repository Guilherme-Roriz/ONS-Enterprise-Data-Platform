from __future__ import annotations

from pathlib import Path

import pytest
from sqlalchemy import text

from ETL.data_vault.core.engine import ETLIngestionEngine


pytestmark = [pytest.mark.integration, pytest.mark.failure_path]


def _write_mapping(root: Path, source: str, sql: str) -> tuple[Path, Path]:
    mappings = root / "mappings"
    sql_dir = root / "sql"
    mappings.mkdir()
    sql_dir.mkdir()
    (mappings / "010_failure.yaml").write_text(
        "pipeline: controlled_failure\n"
        "order: 10\n"
        f"source: {source}\n"
        "targets: [data_vault.hub_state]\n"
        "sql_file: failure.sql\n",
        encoding="utf-8",
    )
    (sql_dir / "failure.sql").write_text(sql, encoding="utf-8")
    return mappings, sql_dir


@pytest.mark.parametrize(
    ("environment", "label"),
    [
        ({"DB_PASSWORD": "definitely-wrong"}, "invalid password"),
        ({"DB_PORT": "1"}, "unavailable database"),
    ],
)
def test_process_returns_nonzero_for_database_connection_failures(
    reset_database, run_seed, environment, label
):
    reset_database()
    result = run_seed(environment=environment, timeout=30)
    assert result.returncode != 0, f"{label} unexpectedly returned success"


@pytest.mark.parametrize("missing_source", ["missing_schema.table", "oltp.missing_table"])
def test_missing_schema_or_table_is_audited_as_failed(
    tmp_path, etl_engine, reset_database, missing_source
):
    reset_database()
    mappings, sql_dir = _write_mapping(
        tmp_path,
        missing_source,
        f"SELECT count(*) FROM {missing_source};",
    )

    with pytest.raises(Exception):
        ETLIngestionEngine(etl_engine, mappings, sql_dir).run()

    with etl_engine.connect() as connection:
        audit = connection.execute(
            text(
                "SELECT status, rows_processed, error_message "
                "FROM etl.etl_control ORDER BY etl_control_id DESC LIMIT 1"
            )
        ).one()
    assert audit.status == "FAILED"
    assert audit.rows_processed == 0
    assert "does not exist" in audit.error_message


def test_mid_transaction_failure_rolls_back_and_clean_rerun_succeeds(
    tmp_path, etl_engine, reset_database
):
    reset_database()
    mappings, sql_dir = _write_mapping(
        tmp_path,
        "oltp.state",
        """
        DO $$
        BEGIN
            INSERT INTO data_vault.hub_state (hash_key_state, state_code)
            VALUES (repeat('f', 64), 'RB');
            RAISE EXCEPTION 'forced mid-transaction failure';
        END $$;
        """,
    )
    pipeline = ETLIngestionEngine(etl_engine, mappings, sql_dir)

    with pytest.raises(Exception, match="forced mid-transaction failure"):
        pipeline.run()

    with etl_engine.connect() as connection:
        assert connection.execute(
            text("SELECT count(*) FROM data_vault.hub_state WHERE state_code = 'RB'")
        ).scalar_one() == 0
        assert connection.execute(
            text(
                "SELECT count(*) FROM etl.etl_control "
                "WHERE pipeline = 'data_vault.controlled_failure' "
                "AND status = 'FAILED'"
            )
        ).scalar_one() == 1

    (sql_dir / "failure.sql").write_text(
        """
        WITH inserted AS (
            INSERT INTO data_vault.hub_state (hash_key_state, state_code)
            VALUES (repeat('f', 64), 'RB')
            ON CONFLICT (hash_key_state) DO NOTHING
            RETURNING 1
        )
        SELECT count(*) FROM inserted;
        """,
        encoding="utf-8",
    )
    pipeline.run()

    with etl_engine.connect() as connection:
        assert connection.execute(
            text("SELECT count(*) FROM data_vault.hub_state WHERE state_code = 'RB'")
        ).scalar_one() == 1
        assert connection.execute(
            text(
                "SELECT status FROM etl.etl_control "
                "WHERE pipeline = 'data_vault.controlled_failure' "
                "ORDER BY etl_control_id DESC LIMIT 1"
            )
        ).scalar_one() == "SUCCESS"
