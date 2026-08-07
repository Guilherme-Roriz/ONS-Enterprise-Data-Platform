from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ETL.galaxy.core.engine import DEFAULT_MAPPINGS_DIR, DEFAULT_SQL_DIR, discover_steps


class GalaxyMappingTests(unittest.TestCase):
    def test_project_mappings_are_complete_and_ordered(self) -> None:
        steps = discover_steps()

        self.assertEqual(14, len(steps))
        self.assertEqual(sorted(step.order for step in steps), [step.order for step in steps])
        self.assertEqual("dim_date", steps[0].name)
        self.assertEqual("fact_asset_status", steps[-1].name)
        self.assertEqual(14, len({step.target for step in steps}))

    def test_every_mapping_has_a_nonempty_sql_statement(self) -> None:
        for step in discover_steps(DEFAULT_MAPPINGS_DIR, DEFAULT_SQL_DIR):
            sql = step.sql_file.read_text(encoding="utf-8").strip()
            self.assertTrue(sql, step.name)
            self.assertIn(f"{step.target}", sql, step.name)

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
                "source: data_vault.source\n"
                "target: galaxy.target\n"
                "sql_file: ../outside.sql\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "Invalid SQL file"):
                discover_steps(mappings, sql)


if __name__ == "__main__":
    unittest.main()
