"""
Entry point for the ONS Enterprise Data Platform ETL.
"""
import logging
import sys

from ETL.config.database import get_engine
from ETL.data_vault.core.engine import ETLIngestionEngine
from ETL.utils.logger import setup_logging

def main():
    setup_logging()
    logger = logging.getLogger(__name__)
    logger.info("Starting ONS ETL")

    try:
        engine = get_engine()
        etl_engine = ETLIngestionEngine(engine)
        etl_engine.run()
    except Exception:
        logger.exception("ETL execution aborted with a fatal error")
        sys.exit(1)
    else:
        logger.info("ETL finished successfully")
        sys.exit(0)

if __name__ == "__main__":
    main()
