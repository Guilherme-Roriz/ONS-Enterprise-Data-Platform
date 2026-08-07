"""Command-line entry point for the Data Vault to Galaxy ETL."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import date

from ETL.config.database import get_engine
from ETL.galaxy.core.engine import GalaxyETLEngine
from ETL.utils.logger import setup_logging


def _date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected YYYY-MM-DD") from exc


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Load Data Vault data into Galaxy")
    parser.add_argument(
        "--start-date",
        type=_date,
        default=_date(os.getenv("GALAXY_START_DATE", "2000-01-01")),
        help="calendar start date (default: GALAXY_START_DATE or 2000-01-01)",
    )
    parser.add_argument(
        "--end-date",
        type=_date,
        default=_date(os.getenv("GALAXY_END_DATE", "2050-12-31")),
        help="calendar end date (default: GALAXY_END_DATE or 2050-12-31)",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    setup_logging(os.getenv("LOG_LEVEL", "INFO"))
    logger = logging.getLogger(__name__)
    try:
        GalaxyETLEngine(get_engine(), args.start_date, args.end_date).run()
    except Exception:
        logger.exception("Data Vault to Galaxy ETL aborted")
        return 1
    logger.info("Data Vault to Galaxy ETL completed successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main())
