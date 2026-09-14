from __future__ import annotations

import json
import os
from pathlib import Path

import pytest


pytestmark = [pytest.mark.e2e, pytest.mark.orchestration]


def _pipeline_snapshot(cursor) -> dict[str, object]:
    snapshot: dict[str, object] = {}
    cursor.execute(
        """
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname IN ('oltp', 'data_vault', 'galaxy')
          AND NOT (schemaname = 'galaxy' AND tablename = 'dim_junk_flags')
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
    snapshot["cross_layer_totals"] = [
        str(value) if value is not None else None for value in cursor.fetchone()
    ]
    return snapshot


def test_airflow_orchestrated_pipeline_state(admin_connection):
    expected_runs = int(os.environ["ORCHESTRATION_EXPECTED_RUNS"])
    snapshot_path_value = os.getenv("ORCHESTRATION_SNAPSHOT_PATH")

    with admin_connection.cursor() as cursor:
        if expected_runs == 0:
            for table in (
                "oltp.generation_reading",
                "data_vault.hub_power_plant",
                "galaxy.fact_energy_generation",
                "etl.etl_control",
            ):
                cursor.execute(f"SELECT count(*) FROM {table}")
                assert cursor.fetchone()[0] == 0
            admin_connection.rollback()
            return

        expected_counts = {
            "oltp.plant": 100,
            "oltp.generation_reading": 7_200,
            "data_vault.hub_power_plant": 100,
            "data_vault.sat_gen_reading": 7_200,
            "galaxy.dim_power_plant": 100,
            "galaxy.fact_energy_generation": 7_200,
            "galaxy.fact_energy_transmission": 36_000,
            "galaxy.fact_power_system_monitoring": 50_400,
            "galaxy.fact_asset_status": 2_400,
        }
        for table, expected_count in expected_counts.items():
            cursor.execute(f"SELECT count(*) FROM {table}")
            assert cursor.fetchone()[0] == expected_count

        cursor.execute(
            "SELECT status, count(*) FROM etl.etl_control GROUP BY status"
        )
        assert dict(cursor.fetchall()) == {"SUCCESS": 27 * expected_runs}

        snapshot = _pipeline_snapshot(cursor)

    admin_connection.rollback()

    if snapshot_path_value:
        snapshot_path = Path(snapshot_path_value)
        if expected_runs == 1:
            snapshot_path.write_text(
                json.dumps(snapshot, sort_keys=True, indent=2), encoding="utf-8"
            )
        elif expected_runs == 2:
            first_snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
            assert snapshot == first_snapshot
