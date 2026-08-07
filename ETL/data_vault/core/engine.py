"""Configuration-driven OLTP to Data Vault transformation engine."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import datetime, timezone
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
    """One ordered OLTP to Data Vault transformation."""

    name: str
    order: int
    source: str
    targets: tuple[str, ...]
    sql_file: Path


def discover_steps(
    mappings_dir: Path = DEFAULT_MAPPINGS_DIR,
    sql_dir: Path = DEFAULT_SQL_DIR,
) -> list[PipelineStep]:
    """Load and validate all first-stage YAML mappings."""
    steps: list[PipelineStep] = []
    sql_root = sql_dir.resolve()

    for mapping_path in sorted(mappings_dir.glob("*.yaml")):
        with mapping_path.open("r", encoding="utf-8") as stream:
            mapping: dict[str, Any] = yaml.safe_load(stream) or {}

        required = {"pipeline", "order", "source", "targets", "sql_file"}
        missing = required.difference(mapping)
        if missing:
            raise ValueError(
                f"{mapping_path.name} is missing: {', '.join(sorted(missing))}"
            )

        source = str(mapping["source"])
        targets = tuple(str(target) for target in mapping["targets"])
        if not IDENTIFIER.fullmatch(source):
            raise ValueError(
                f"Unsafe source identifier in {mapping_path.name}: {source}"
            )
        if not targets or any(not IDENTIFIER.fullmatch(target) for target in targets):
            raise ValueError(f"Invalid target list in {mapping_path.name}")

        sql_path = (sql_dir / str(mapping["sql_file"])).resolve()
        if sql_root not in sql_path.parents or not sql_path.is_file():
            raise ValueError(f"Invalid SQL file in {mapping_path.name}: {sql_path}")

        steps.append(
            PipelineStep(
                name=str(mapping["pipeline"]),
                order=int(mapping["order"]),
                source=source,
                targets=targets,
                sql_file=sql_path,
            )
        )

    if not steps:
        raise RuntimeError(f"No Data Vault mappings found in {mappings_dir}")
    if len({step.name for step in steps}) != len(steps):
        raise ValueError("Data Vault pipeline names must be unique")
    if len({step.order for step in steps}) != len(steps):
        raise ValueError("Data Vault pipeline order values must be unique")
    return sorted(steps, key=lambda step: step.order)


class ETLIngestionEngine:
    """Run ordered, transactional and idempotent Data Vault loads."""

    def __init__(
        self,
        db_engine: Engine,
        mappings_dir: Path = DEFAULT_MAPPINGS_DIR,
        sql_dir: Path = DEFAULT_SQL_DIR,
    ) -> None:
        self.engine = db_engine
        self.steps = discover_steps(mappings_dir, sql_dir)
        self.control = ETLControl()

    @staticmethod
    def _target_label(step: PipelineStep) -> str:
        return ",".join(step.targets)

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
                "pipeline": f"data_vault.{step.name}",
                "source": step.source,
                "target": self._target_label(step),
                "rows_processed": rows_processed,
                "started_at": started_at,
                "ended_at": ended_at,
                "execution_time": (ended_at - started_at).total_seconds(),
                "status": status,
                "error_message": error_message,
            },
        )

    def run(self) -> None:
        """Execute all configured steps and stop immediately after a failure."""
        with self.engine.begin() as conn:
            self.control.ensure_table(conn)

        for step in self.steps:
            started_at = datetime.now(timezone.utc)
            logger.info(
                "Starting Data Vault step %s: %s -> %s",
                step.name,
                step.source,
                self._target_label(step),
            )
            try:
                with self.engine.begin() as conn:
                    result = conn.execute(
                        text(step.sql_file.read_text(encoding="utf-8"))
                    )
                    affected = int(result.scalar_one())
                    ended_at = datetime.now(timezone.utc)
                    self._audit(conn, step, started_at, ended_at, affected, "SUCCESS")
            except Exception as exc:
                ended_at = datetime.now(timezone.utc)
                logger.exception("Data Vault step %s failed", step.name)
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
                "Completed Data Vault step %s: %d rows affected in %.3fs",
                step.name,
                affected,
                (ended_at - started_at).total_seconds(),
            )
