"""
Generic ETL ingestion engine.
Processes all YAML mappings, orchestrating the Data Vault loaders.
"""
import logging
from datetime import datetime, timezone
from pathlib import Path
import pandas as pd
import yaml
from sqlalchemy import Engine

from ETL.common.control import ETLControl
from ETL.data_vault.core.hub_loader import HubLoader
from ETL.data_vault.core.link_loader import LinkLoader
from ETL.data_vault.core.satellite_loader import SatelliteLoader

logger = logging.getLogger(__name__)

MAPPINGS_DIR = Path(__file__).resolve().parent.parent / "mappings"


class ETLIngestionEngine:
    """
    Configuration-driven engine that loads OLTP data into the Data Vault.
    """

    def __init__(self, db_engine: Engine):
        self.engine = db_engine
        self.hub_loader = HubLoader()
        self.sat_loader = SatelliteLoader()
        self.link_loader = LinkLoader()
        self.control = ETLControl()

    def run(self) -> None:
        """Main entry point: process all mapping files."""
        mapping_files = sorted(
            path
            for pattern in ("*.yaml", "*.yml", "*.yalm")
            for path in MAPPINGS_DIR.glob(pattern)
        )
        if not mapping_files:
            logger.warning("No YAML mapping files found in %s", MAPPINGS_DIR)
            return

        with self.engine.begin() as conn:
            self.control.ensure_table(conn)

        for mapping_path in mapping_files:
            with open(mapping_path, "r", encoding="utf-8") as f:
                mapping = yaml.safe_load(f)

            pipeline_name = mapping_path.stem
            source_table = mapping["source_table"]
            logger.info("="*60)
            logger.info("Starting pipeline '%s' for source %s", pipeline_name, source_table)

            start_time = datetime.now(timezone.utc)
            rows_processed = 0
            status = "SUCCESS"
            last_id = 0

            try:
                with self.engine.begin() as conn:
                    # 1. Determine incremental boundary
                    last_id = self.control.get_last_processed_id(conn, pipeline_name, source_table)
                    incremental_col = mapping.get("incremental_column", "id")
                    logger.info("Last processed %s = %s", incremental_col, last_id)

                    # 2. Read source data
                    query = f"SELECT * FROM {source_table} WHERE {incremental_col} > {last_id} ORDER BY {incremental_col}"
                    df = pd.read_sql(query, conn)
                    rows_processed = len(df)
                    logger.info("Read %d rows from %s", rows_processed, source_table)

                    if df.empty:
                        logger.info("No new rows. Skipping loading.")
                        end_time = datetime.now(timezone.utc)
                        self.control.update_control(
                            conn, pipeline_name, source_table, last_id,
                            rows_processed, "SUCCESS", start_time, end_time,
                        )
                        continue

                    # 3. Load Hub
                    if "hub_table" in mapping:
                        self.hub_loader.load(conn, mapping, df)

                    # 4. Load Satellite
                    if "satellite_table" in mapping:
                        self.sat_loader.load(conn, mapping, df)

                    # 5. Load Links (if defined)
                    self.link_loader.load(conn, mapping, df)

                    # 6. Update control with new high-water mark
                    new_max_id = int(df[incremental_col].max())
                    end_time = datetime.now(timezone.utc)
                    self.control.update_control(
                        conn, pipeline_name, source_table, new_max_id,
                        rows_processed, "SUCCESS", start_time, end_time,
                    )

            except Exception:
                logger.exception("Pipeline '%s' failed", pipeline_name)
                # Attempt to log failure to control table outside the failed transaction
                with self.engine.begin() as err_conn:
                    end_time = datetime.now(timezone.utc)
                    self.control.update_control(
                        err_conn, pipeline_name, source_table, last_id,
                        0, "FAILED", start_time, end_time,
                    )
                status = "FAILED"

            logger.info(
                "Pipeline '%s' completed with status %s (duration %s)",
                pipeline_name,
                status,
                (datetime.now(timezone.utc) - start_time).total_seconds(),
            )
