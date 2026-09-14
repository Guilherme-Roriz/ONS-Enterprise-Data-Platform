from __future__ import annotations

import pytest

from ETL.common.control import ETLControl


pytestmark = pytest.mark.unit


class RecordingConnection:
    def __init__(self) -> None:
        self.statements: list[str] = []

    def execute(self, statement):
        self.statements.append(str(statement))


def test_control_bootstrap_respects_least_privilege_schema_boundary() -> None:
    connection = RecordingConnection()
    ETLControl.ensure_table(connection)

    assert connection.statements
    assert all("CREATE SCHEMA" not in statement for statement in connection.statements)
    assert any("CREATE TABLE IF NOT EXISTS etl.etl_control" in statement for statement in connection.statements)
