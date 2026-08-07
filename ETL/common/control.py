"""
ETL control-table operations shared by both pipeline stages.
Tracks the last processed incremental key per source table.
"""
import logging
from datetime import datetime

from sqlalchemy import Connection, text

logger = logging.getLogger(__name__)

CONTROL_TABLE = "etl.etl_control"

class ETLControl:
    """Manage the etl_control table for incremental loading."""

    @staticmethod
    def get_last_processed_id(conn: Connection, pipeline: str, source_table: str) -> int:
        """
        Retrieve the last processed ID for the given pipeline and source table.
        Returns 0 if no record exists (initial load).
        """
        query = text("""
            SELECT last_processed_id
            FROM etl.etl_control
            WHERE pipeline = :pipeline AND source_table = :source_table
            ORDER BY execution_end DESC
            LIMIT 1
        """)
        result = conn.execute(query, {"pipeline": pipeline, "source_table": source_table}).scalar()
        return result if result is not None else 0

    @staticmethod
    def update_control(
        conn: Connection,
        pipeline: str,
        source_table: str,
        last_processed_id: int,
        rows_processed: int,
        status: str,
        execution_start: datetime,
        execution_end: datetime,
    ) -> None:
        """
        Insert a new control record after a pipeline run.
        Execution time is derived from the two timestamps.
        """
        execution_time = (execution_end - execution_start).total_seconds()
        insert_sql = text("""
            INSERT INTO etl.etl_control
                (pipeline, source_table, last_processed_id, rows_processed,
                 execution_start, execution_end, execution_time, status)
            VALUES
                (:pipeline, :source_table, :last_id, :rows_proc,
                 :start, :end, :exec_time, :status)
        """)
        conn.execute(
            insert_sql,
            {
                "pipeline": pipeline,
                "source_table": source_table,
                "last_id": last_processed_id,
                "rows_proc": rows_processed,
                "start": execution_start,
                "end": execution_end,
                "exec_time": execution_time,
                "status": status,
            },
        )
        logger.info(
            "Control record inserted for %s/%s, status=%s, rows=%s",
            pipeline, source_table, status, rows_processed,
        )

    @staticmethod
    def ensure_table(conn: Connection) -> None:
        """Create the shared audit table when the ETL is run on a new database."""
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS etl"))
        conn.execute(text("""
            CREATE TABLE IF NOT EXISTS etl.etl_control (
                execution_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                pipeline VARCHAR(100) NOT NULL,
                source_table VARCHAR(200) NOT NULL,
                target_table VARCHAR(200),
                last_processed_id BIGINT NOT NULL DEFAULT 0,
                rows_processed BIGINT NOT NULL DEFAULT 0,
                execution_start TIMESTAMPTZ NOT NULL,
                execution_end TIMESTAMPTZ NOT NULL,
                execution_time DECIMAL(14,3) NOT NULL,
                status VARCHAR(20) NOT NULL CHECK (status IN ('SUCCESS', 'FAILED')),
                error_message TEXT
            )
        """))
        conn.execute(text("""
            ALTER TABLE etl.etl_control
            ADD COLUMN IF NOT EXISTS target_table VARCHAR(200)
        """))
        conn.execute(text("""
            ALTER TABLE etl.etl_control
            ADD COLUMN IF NOT EXISTS error_message TEXT
        """))
        conn.execute(text("""
            CREATE INDEX IF NOT EXISTS idx_etl_control_pipeline_latest
            ON etl.etl_control (pipeline, source_table, execution_end DESC)
        """))
