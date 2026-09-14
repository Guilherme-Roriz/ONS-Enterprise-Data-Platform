from __future__ import annotations

import pytest


pytestmark = pytest.mark.integration


def _assert_success(result, stage):
    assert result.returncode == 0, (
        f"{stage} failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_power_plant_change_creates_non_overlapping_scd2_version(
    admin_connection, reset_database, run_seed, run_vault, run_galaxy
):
    reset_database()
    _assert_success(run_seed(), "seed")
    _assert_success(run_vault(), "initial Data Vault")
    _assert_success(run_galaxy(), "initial Galaxy")

    with admin_connection.cursor() as cursor:
        cursor.execute(
            """
            UPDATE oltp.plant
            SET installed_capacity = installed_capacity + 1,
                last_updated = last_updated + interval '1 day'
            WHERE plant_code = 'PLT-001'
            """
        )
    admin_connection.commit()

    _assert_success(run_vault(), "changed Data Vault")
    _assert_success(run_galaxy(), "changed Galaxy")

    with admin_connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT count(*),
                   count(*) FILTER (WHERE end_date IS NULL),
                   bool_and(end_date IS NULL OR start_date < end_date)
            FROM data_vault.sat_power_plant_attributes AS satellite
            JOIN data_vault.hub_power_plant AS hub USING (hash_key_power_plant)
            WHERE hub.plant_code = 'PLT-001'
            """
        )
        assert cursor.fetchone() == (2, 1, True)

        cursor.execute(
            """
            SELECT count(*),
                   count(*) FILTER (WHERE end_date IS NULL),
                   bool_and(end_date IS NULL OR start_date < end_date)
            FROM galaxy.dim_power_plant AS dimension
            JOIN data_vault.hub_power_plant AS hub USING (hash_key_power_plant)
            WHERE hub.plant_code = 'PLT-001'
            """
        )
        assert cursor.fetchone() == (2, 1, True)
    admin_connection.rollback()
