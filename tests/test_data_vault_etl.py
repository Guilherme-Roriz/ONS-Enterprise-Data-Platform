from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ETL.data_vault.core.engine import (
    DEFAULT_MAPPINGS_DIR,
    DEFAULT_SQL_DIR,
    discover_steps,
)

EXPECTED_TARGETS = {
    "data_vault.hub_power_plant",
    "data_vault.hub_transmission_line",
    "data_vault.hub_substation",
    "data_vault.hub_occurrence",
    "data_vault.hub_work_order",
    "data_vault.hub_state",
    "data_vault.hub_occurrence_type",
    "data_vault.hub_maintenance_type",
    "data_vault.link_occurrence_power_plant",
    "data_vault.link_occurrence_substation",
    "data_vault.link_occurrence_transmission_line",
    "data_vault.link_work_order_power_plant",
    "data_vault.link_work_order_substation",
    "data_vault.link_work_order_transmission_line",
    "data_vault.link_power_plant_state",
    "data_vault.link_substation_state",
    "data_vault.link_transmission_line_substation",
    "data_vault.sat_power_plant_attributes",
    "data_vault.sat_power_plant_status",
    "data_vault.sat_power_plant_daily_snapshot",
    "data_vault.sat_line_attributes",
    "data_vault.sat_line_status",
    "data_vault.sat_line_daily_snapshot",
    "data_vault.sat_substation_attributes",
    "data_vault.sat_substation_status",
    "data_vault.sat_substation_daily_snapshot",
    "data_vault.sat_occurrence_detail",
    "data_vault.sat_work_order_detail",
    "data_vault.sat_state_attributes",
    "data_vault.sat_occurrence_type_attributes",
    "data_vault.sat_maintenance_type_attributes",
    "data_vault.sat_gen_reading",
    "data_vault.sat_substation_measurement",
    "data_vault.sat_line_measurement",
}

EXPECTED_SOURCES = {
    "oltp.state",
    "oltp.occurrence_type",
    "oltp.maintenance_type",
    "oltp.plant",
    "oltp.substation",
    "oltp.transmission_line",
    "oltp.generation_reading",
    "oltp.measurement",
    "oltp.occurrence",
    "oltp.occurrence_asset",
    "oltp.work_order",
    "oltp.work_order_asset",
    "oltp.asset_status",
}


class DataVaultMappingTests(unittest.TestCase):
    def test_project_mappings_cover_the_complete_vault(self) -> None:
        steps = discover_steps()
        targets = {target for step in steps for target in step.targets}
        sources = {step.source for step in steps}

        self.assertEqual(13, len(steps))
        self.assertEqual(EXPECTED_SOURCES, sources)
        self.assertEqual(EXPECTED_TARGETS, targets)
        self.assertEqual(
            len(EXPECTED_TARGETS),
            sum(len(step.targets) for step in steps),
            "each Vault table should have one owning source-domain mapping",
        )
        self.assertEqual(
            sorted(step.order for step in steps), [step.order for step in steps]
        )
        self.assertEqual("state", steps[0].name)
        self.assertEqual("asset_status", steps[-1].name)

    def test_every_mapping_has_sql_for_each_declared_target(self) -> None:
        for step in discover_steps(DEFAULT_MAPPINGS_DIR, DEFAULT_SQL_DIR):
            sql = step.sql_file.read_text(encoding="utf-8")
            self.assertIn("rows_processed", sql, step.name)
            for target in step.targets:
                self.assertIn(target, sql, f"{step.name}: {target}")

    def test_rejects_sql_path_outside_sql_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            mappings = root / "mappings"
            sql = root / "sql"
            mappings.mkdir()
            sql.mkdir()
            (root / "outside.sql").write_text("SELECT 1", encoding="utf-8")
            (mappings / "bad.yaml").write_text(
                "pipeline: bad\n"
                "order: 1\n"
                "source: oltp.source\n"
                "targets:\n"
                "  - data_vault.target\n"
                "sql_file: ../outside.sql\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "Invalid SQL file"):
                discover_steps(mappings, sql)


if __name__ == "__main__":
    unittest.main()
