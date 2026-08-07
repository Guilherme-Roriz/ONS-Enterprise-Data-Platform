"""Shared ETL control-table bootstrap."""

from sqlalchemy import Connection, text


class ETLControl:
    """Create and evolve the execution-audit table used by both stages."""

    @staticmethod
    def ensure_table(conn: Connection) -> None:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS etl"))
        conn.execute(
            text("""
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
        """)
        )
        conn.execute(
            text("""
            ALTER TABLE etl.etl_control
            ADD COLUMN IF NOT EXISTS target_table VARCHAR(200)
        """)
        )
        conn.execute(
            text("""
            ALTER TABLE etl.etl_control
            ADD COLUMN IF NOT EXISTS error_message TEXT
        """)
        )
        conn.execute(
            text("""
            CREATE INDEX IF NOT EXISTS idx_etl_control_pipeline_latest
            ON etl.etl_control (pipeline, source_table, execution_end DESC)
        """)
        )
