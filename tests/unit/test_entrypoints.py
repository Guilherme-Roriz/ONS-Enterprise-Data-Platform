from __future__ import annotations

from datetime import date
from unittest.mock import Mock

import pytest

from ETL.data_vault import main as vault_main
from ETL.galaxy import main as galaxy_main


pytestmark = pytest.mark.unit


@pytest.mark.parametrize("module", [vault_main, galaxy_main])
def test_entrypoint_returns_nonzero_when_database_fails(
    module, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(module, "get_engine", Mock(side_effect=RuntimeError("db down")))
    if module is galaxy_main:
        monkeypatch.setattr(
            module,
            "build_parser",
            Mock(
                return_value=Mock(
                    parse_args=Mock(
                        return_value=Mock(
                            start_date=date(2026, 7, 1), end_date=date(2026, 7, 3)
                        )
                    )
                )
            ),
        )
    assert module.main() == 1


def test_vault_entrypoint_returns_zero_after_success(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    engine = Mock()
    runner = Mock()
    monkeypatch.setattr(vault_main, "get_engine", Mock(return_value=engine))
    monkeypatch.setattr(vault_main, "ETLIngestionEngine", Mock(return_value=runner))
    assert vault_main.main() == 0
    runner.run.assert_called_once_with()


def test_galaxy_date_parser_rejects_invalid_value() -> None:
    with pytest.raises(Exception, match="expected YYYY-MM-DD"):
        galaxy_main._date("07/01/2026")

