from __future__ import annotations

import pytest


pytestmark = pytest.mark.data_quality


HUB_CONTRACTS = (
    ("oltp.state", "state_code", "data_vault.hub_state", "state_code", "hash_key_state"),
    ("oltp.occurrence_type", "type_code", "data_vault.hub_occurrence_type", "type_code", "hash_key_occurrence_type"),
    ("oltp.maintenance_type", "type_code", "data_vault.hub_maintenance_type", "type_code", "hash_key_maintenance_type"),
    ("oltp.plant", "plant_code", "data_vault.hub_power_plant", "plant_code", "hash_key_power_plant"),
    ("oltp.substation", "substation_code", "data_vault.hub_substation", "substation_code", "hash_key_substation"),
    ("oltp.transmission_line", "line_code", "data_vault.hub_transmission_line", "line_code", "hash_key_transmission_line"),
    ("oltp.occurrence", "ticket_number", "data_vault.hub_occurrence", "ticket_number", "hash_key_occurrence"),
    ("oltp.work_order", "order_number", "data_vault.hub_work_order", "order_number", "hash_key_work_order"),
)

SCD2_SATELLITES = (
    ("sat_power_plant_attributes", "hash_key_power_plant"),
    ("sat_power_plant_status", "hash_key_power_plant"),
    ("sat_line_attributes", "hash_key_transmission_line"),
    ("sat_line_status", "hash_key_transmission_line"),
    ("sat_substation_attributes", "hash_key_substation"),
    ("sat_substation_status", "hash_key_substation"),
    ("sat_occurrence_detail", "hash_key_occurrence"),
    ("sat_work_order_detail", "hash_key_work_order"),
)

FACT_GRAINS = {
    "fact_energy_generation": "sk_date, sk_time_of_day, sk_power_plant",
    "fact_energy_transmission": "sk_date, sk_time_of_day, sk_transmission_line",
    "fact_power_system_monitoring": "sk_date, sk_time_of_day, COALESCE(sk_substation, -1), COALESCE(sk_transmission_line, -1)",
    "fact_grid_occurrence": "occurrence_id, COALESCE(sk_power_plant, -1), COALESCE(sk_substation, -1), COALESCE(sk_transmission_line, -1)",
    "fact_maintenance": "work_order_number, COALESCE(sk_power_plant, -1), COALESCE(sk_substation, -1), COALESCE(sk_transmission_line, -1)",
    "fact_asset_status": "sk_date, COALESCE(sk_power_plant, -1), COALESCE(sk_substation, -1), COALESCE(sk_transmission_line, -1)",
}


def test_pipeline_has_no_cross_layer_quality_breaks(admin_connection, request):
    if not request.config.getoption("--run-orchestration"):
        request.getfixturevalue("loaded_pipeline")

    with admin_connection.cursor() as cursor:
        for source_table, source_key, hub_table, hub_key, hash_key in HUB_CONTRACTS:
            cursor.execute(f"SELECT count(*) FROM {source_table}")
            source_count = cursor.fetchone()[0]
            cursor.execute(f"SELECT count(*) FROM {hub_table}")
            assert cursor.fetchone()[0] == source_count
            cursor.execute(
                f"""
                SELECT count(*)
                FROM {hub_table}
                WHERE {hash_key} <> encode(sha256(convert_to({hub_key}, 'UTF8')), 'hex')
                """
            )
            assert cursor.fetchone()[0] == 0
            cursor.execute(
                f"""
                SELECT count(*) FROM (
                    SELECT {source_key} FROM {source_table}
                    EXCEPT
                    SELECT {hub_key} FROM {hub_table}
                ) AS missing
                """
            )
            assert cursor.fetchone()[0] == 0

        for table, parent_key in SCD2_SATELLITES:
            cursor.execute(
                f"""
                SELECT count(*) FROM (
                    SELECT {parent_key}
                    FROM data_vault.{table}
                    GROUP BY {parent_key}
                    HAVING count(*) FILTER (WHERE end_date IS NULL) <> 1
                ) AS invalid_current_rows
                """
            )
            assert cursor.fetchone()[0] == 0
            cursor.execute(
                f"""
                SELECT count(*)
                FROM data_vault.{table} AS left_version
                JOIN data_vault.{table} AS right_version
                  ON left_version.{parent_key} = right_version.{parent_key}
                 AND left_version.start_date < right_version.start_date
                 AND COALESCE(left_version.end_date, 'infinity'::date) > right_version.start_date
                """
            )
            assert cursor.fetchone()[0] == 0

        expected_dimensions = {
            "dim_state": 27,
            "dim_power_plant": 100,
            "dim_substation": 200,
            "dim_transmission_line": 500,
            "dim_occurrence_type": 8,
            "dim_maintenance_type": 5,
            "dim_time_of_day": 1_440,
            "dim_junk_flags": 27,
        }
        for table, expected_count in expected_dimensions.items():
            cursor.execute(f"SELECT count(*) FROM galaxy.{table}")
            assert cursor.fetchone()[0] == expected_count

        cursor.execute(
            """
            SELECT min(full_date), max(full_date), count(*),
                   max(full_date) - min(full_date) + 1
            FROM galaxy.dim_date
            """
        )
        minimum, maximum, row_count, inclusive_days = cursor.fetchone()
        assert minimum.isoformat() == "2026-07-01"
        assert maximum.isoformat() >= "2026-07-03"
        assert row_count == inclusive_days

        expected_facts = {
            "fact_energy_generation": 7_200,
            "fact_energy_transmission": 36_000,
            "fact_power_system_monitoring": 50_400,
            "fact_asset_status": 2_400,
        }
        for table, expected_count in expected_facts.items():
            cursor.execute(f"SELECT count(*) FROM galaxy.{table}")
            assert cursor.fetchone()[0] == expected_count

        for table, grain in FACT_GRAINS.items():
            cursor.execute(
                f"SELECT count(*) - count(DISTINCT ({grain})) FROM galaxy.{table}"
            )
            assert cursor.fetchone()[0] == 0

        cursor.execute("SELECT count(*) FROM galaxy.fact_grid_occurrence")
        occurrence_fact_count = cursor.fetchone()[0]
        cursor.execute("SELECT count(*) FROM oltp.occurrence_asset")
        assert occurrence_fact_count == cursor.fetchone()[0]

        cursor.execute("SELECT count(*) FROM galaxy.fact_maintenance")
        maintenance_fact_count = cursor.fetchone()[0]
        cursor.execute("SELECT count(*) FROM oltp.work_order_asset")
        assert maintenance_fact_count == cursor.fetchone()[0]

        cursor.execute(
            """
            SELECT
                (SELECT sum(generation_output_mw) FROM oltp.generation_reading),
                (SELECT sum(generation_output_mw) FROM data_vault.sat_gen_reading),
                (SELECT sum(generation_output_mw) FROM galaxy.fact_energy_generation)
            """
        )
        source_total, vault_total, galaxy_total = cursor.fetchone()
        assert source_total == vault_total == galaxy_total
    admin_connection.rollback()
