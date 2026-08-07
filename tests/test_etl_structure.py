from __future__ import annotations

import unittest

from ETL.common.control import ETLControl
from ETL.data_vault.core.engine import DEFAULT_MAPPINGS_DIR, ETLIngestionEngine
from ETL.galaxy.core.engine import GalaxyETLEngine


class ETLStructureTests(unittest.TestCase):
    def test_stages_are_separate_packages(self) -> None:
        self.assertEqual("data_vault", DEFAULT_MAPPINGS_DIR.parent.name)
        self.assertEqual("mappings", DEFAULT_MAPPINGS_DIR.name)
        self.assertTrue(ETLIngestionEngine.__module__.startswith("ETL.data_vault."))
        self.assertTrue(GalaxyETLEngine.__module__.startswith("ETL.galaxy."))

    def test_control_is_shared_infrastructure(self) -> None:
        self.assertEqual("ETL.common.control", ETLControl.__module__)


if __name__ == "__main__":
    unittest.main()
