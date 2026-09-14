from __future__ import annotations

import pytest


pytestmark = pytest.mark.integration


EXPECTED_COUNTS = {
    "state": 27,
    "occurrence_type": 8,
    "maintenance_type": 5,
    "plant": 100,
    "substation": 200,
    "transmission_line": 500,
    "generation_reading": 7_200,
    "measurement": 50_400,
    "occurrence": 100,
    "work_order": 50,
    "asset_status": 2_400,
}


def _counts(connection):
    result = {}
    with connection.cursor() as cursor:
        for table in EXPECTED_COUNTS:
            cursor.execute(f"SELECT count(*) FROM oltp.{table}")
            result[table] = cursor.fetchone()[0]
        for table in ("occurrence_asset", "work_order_asset"):
            cursor.execute(f"SELECT count(*) FROM oltp.{table}")
            result[table] = cursor.fetchone()[0]
    connection.rollback()
    return result


def _fingerprint(connection):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT md5(string_agg(payload, '|' ORDER BY payload))
            FROM (
                SELECT plant_code || ':' || plant_name || ':' || state_id AS payload
                FROM oltp.plant
                UNION ALL
                SELECT plant_id || ':' || reading_timestamp || ':' || generation_output_mw
                FROM oltp.generation_reading
            ) AS rows
            """
        )
        value = cursor.fetchone()[0]
    connection.rollback()
    return value


def _assert_success(result, stage="seed"):
    assert result.returncode == 0, (
        f"{stage} failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_seed_first_run_rerun_and_deterministic_rebuild(
    admin_connection, reset_database, run_seed
):
    reset_database()
    _assert_success(run_seed(), "first seed")
    first_counts = _counts(admin_connection)
    first_fingerprint = _fingerprint(admin_connection)

    assert {key: first_counts[key] for key in EXPECTED_COUNTS} == EXPECTED_COUNTS
    assert first_counts["occurrence_asset"] >= EXPECTED_COUNTS["occurrence"]
    assert first_counts["work_order_asset"] >= EXPECTED_COUNTS["work_order"]

    _assert_success(run_seed(), "seed rerun")
    assert _counts(admin_connection) == first_counts
    assert _fingerprint(admin_connection) == first_fingerprint

    reset_database()
    _assert_success(run_seed(), "deterministic rebuild")
    assert _counts(admin_connection) == first_counts
    assert _fingerprint(admin_connection) == first_fingerprint


def test_seed_reconciles_partial_state_using_real_business_key_ids(
    admin_connection, reset_database, run_seed
):
    reset_database()
    with admin_connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO oltp.state (state_id, state_code, state_name, ons_control_area)
            OVERRIDING SYSTEM VALUE
            VALUES (900, 'AC', 'Acre', 'Pre-existing control area')
            """
        )
    admin_connection.commit()

    _assert_success(run_seed(), "partial-state reconciliation")

    with admin_connection.cursor() as cursor:
        cursor.execute("SELECT state_id FROM oltp.state WHERE state_code = 'AC'")
        assert cursor.fetchone()[0] == 900
        cursor.execute("SELECT count(*) FROM oltp.state")
        assert cursor.fetchone()[0] == 27
        cursor.execute(
            "SELECT count(*) FROM oltp.plant WHERE state_id = 900"
        )
        assert cursor.fetchone()[0] > 0
        cursor.execute(
            """
            SELECT count(*)
            FROM oltp.plant AS plant
            LEFT JOIN oltp.state AS state ON state.state_id = plant.state_id
            WHERE state.state_id IS NULL
            """
        )
        assert cursor.fetchone()[0] == 0
    admin_connection.rollback()
