from __future__ import annotations

import pytest


pytestmark = pytest.mark.e2e


def _assert_success(result, stage):
    assert result.returncode == 0, (
        f"{stage} failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def _pipeline_snapshot(connection):
    snapshot = {}
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT schemaname, tablename
            FROM pg_tables
            WHERE schemaname IN ('oltp', 'data_vault', 'galaxy')
            ORDER BY schemaname, tablename
            """
        )
        for schema, table in cursor.fetchall():
            cursor.execute(f"SELECT count(*) FROM {schema}.{table}")
            snapshot[f"{schema}.{table}"] = cursor.fetchone()[0]

        cursor.execute(
            """
            SELECT
                (SELECT sum(generation_output_mw) FROM oltp.generation_reading),
                (SELECT sum(generation_output_mw) FROM data_vault.sat_gen_reading),
                (SELECT sum(generation_output_mw) FROM galaxy.fact_energy_generation),
                (SELECT sum(availability_pct) FROM oltp.asset_status),
                (SELECT sum(availability_pct) FROM galaxy.fact_asset_status)
            """
        )
        snapshot["cross_layer_totals"] = cursor.fetchone()
    connection.rollback()
    return snapshot


def test_empty_database_bootstrap_to_consistent_idempotent_rerun(
    admin_connection, reset_database, run_seed, run_vault, run_galaxy
):
    reset_database()
    stages = (
        ("seed OLTP", run_seed),
        ("OLTP to Data Vault", run_vault),
        ("Data Vault to Galaxy", run_galaxy),
    )

    for stage, run in stages:
        _assert_success(run(), stage)
    first_snapshot = _pipeline_snapshot(admin_connection)

    assert first_snapshot["oltp.generation_reading"] == 7_200
    assert first_snapshot["data_vault.sat_gen_reading"] == 7_200
    assert first_snapshot["galaxy.fact_energy_generation"] == 7_200

    for stage, run in stages:
        _assert_success(run(), f"rerun {stage}")
    second_snapshot = _pipeline_snapshot(admin_connection)

    assert second_snapshot == first_snapshot
    with admin_connection.cursor() as cursor:
        cursor.execute("SELECT status, count(*) FROM etl.etl_control GROUP BY status")
        assert dict(cursor.fetchall()) == {"SUCCESS": 54}
    admin_connection.rollback()
