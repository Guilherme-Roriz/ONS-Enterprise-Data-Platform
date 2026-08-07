"""Configuration-driven Data Vault to Galaxy SQL transformation engine."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import yaml
from sqlalchemy import Connection, Engine, text

from ETL.common.control import ETLControl


logger = logging.getLogger(__name__)
PACKAGE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_MAPPINGS_DIR = PACKAGE_DIR / "mappings"
DEFAULT_SQL_DIR = PACKAGE_DIR / "sql"
IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$")


@dataclass(frozen=True)
class PipelineStep:
    """One ordered, configuration-defined Galaxy transformation."""

    name: str
    order: int
    source: str
    target: str
    sql_file: Path


def discover_steps(
    mappings_dir: Path = DEFAULT_MAPPINGS_DIR,
    sql_dir: Path = DEFAULT_SQL_DIR,
) -> list[PipelineStep]:
    """Load and validate all Galaxy YAML mappings in execution order."""
    steps: list[PipelineStep] = []
    sql_root = sql_dir.resolve()

    for mapping_path in sorted(mappings_dir.glob("*.yaml")):
        with mapping_path.open("r", encoding="utf-8") as stream:
            mapping: dict[str, Any] = yaml.safe_load(stream) or {}

        required = {"pipeline", "order", "source", "target", "sql_file"}
        missing = required.difference(mapping)
        if missing:
            raise ValueError(
                f"{mapping_path.name} is missing: {', '.join(sorted(missing))}"
            )

        target = str(mapping["target"])
        if not IDENTIFIER.fullmatch(target):
            raise ValueError(f"Unsafe target identifier in {mapping_path.name}: {target}")

        sql_path = (sql_dir / str(mapping["sql_file"])).resolve()
        if sql_root not in sql_path.parents or not sql_path.is_file():
            raise ValueError(f"Invalid SQL file in {mapping_path.name}: {sql_path}")

        steps.append(
            PipelineStep(
                name=str(mapping["pipeline"]),
                order=int(mapping["order"]),
                source=str(mapping["source"]),
                target=target,
                sql_file=sql_path,
            )
        )

    if not steps:
        raise RuntimeError(f"No Galaxy mappings found in {mappings_dir}")
    if len({step.name for step in steps}) != len(steps):
        raise ValueError("Galaxy pipeline names must be unique")
    if len({step.order for step in steps}) != len(steps):
        raise ValueError("Galaxy pipeline order values must be unique")
    return sorted(steps, key=lambda step: step.order)


class GalaxyETLEngine:
    """Run ordered, transactional and idempotent Galaxy transformations."""

    def __init__(
        self,
        db_engine: Engine,
        start_date: date,
        end_date: date,
        mappings_dir: Path = DEFAULT_MAPPINGS_DIR,
        sql_dir: Path = DEFAULT_SQL_DIR,
    ) -> None:
        if start_date > end_date:
            raise ValueError("Galaxy calendar start date must not be after end date")
        self.engine = db_engine
        self.start_date = start_date
        self.end_date = end_date
        self.steps = discover_steps(mappings_dir, sql_dir)
        self.control = ETLControl()

    def _audit(
        self,
        conn: Connection,
        step: PipelineStep,
        started_at: datetime,
        ended_at: datetime,
        rows_processed: int,
        status: str,
        error_message: str | None = None,
    ) -> None:
        conn.execute(
            text("""
                INSERT INTO etl.etl_control (
                    pipeline, source_table, target_table, last_processed_id,
                    rows_processed, execution_start, execution_end,
                    execution_time, status, error_message
                ) VALUES (
                    :pipeline, :source, :target, 0,
                    :rows_processed, :started_at, :ended_at,
                    :execution_time, :status, :error_message
                )
            """),
            {
                "pipeline": f"galaxy.{step.name}",
                "source": step.source,
                "target": step.target,
                "rows_processed": rows_processed,
                "started_at": started_at,
                "ended_at": ended_at,
                "execution_time": (ended_at - started_at).total_seconds(),
                "status": status,
                "error_message": error_message,
            },
        )

    def run(self) -> None:
        """Execute every configured step; stop immediately on a failed step."""
        with self.engine.begin() as conn:
            self.control.ensure_table(conn)

        for step in self.steps:
            started_at = datetime.now(timezone.utc)
            logger.info("Starting Galaxy step %s -> %s", step.name, step.target)
            try:
                with self.engine.begin() as conn:
                    statement = text(step.sql_file.read_text(encoding="utf-8"))
                    result = conn.execute(
                        statement,
                        {
                            "start_date": self.start_date,
                            "end_date": self.end_date,
                        },
                    )
                    affected = max(result.rowcount or 0, 0)
                    ended_at = datetime.now(timezone.utc)
                    self._audit(
                        conn, step, started_at, ended_at, affected, "SUCCESS"
                    )
            except Exception as exc:
                ended_at = datetime.now(timezone.utc)
                logger.exception("Galaxy step %s failed", step.name)
                with self.engine.begin() as conn:
                    self._audit(
                        conn,
                        step,
                        started_at,
                        ended_at,
                        0,
                        "FAILED",
                        str(exc)[:4000],
                    )
                raise

            logger.info(
                "Completed Galaxy step %s: %d rows affected in %.3fs",
                step.name,
                affected,
                (ended_at - started_at).total_seconds(),
            )
