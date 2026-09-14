from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator

import psycopg2
import pytest
from sqlalchemy import Engine, create_engine


PROJECT_ROOT = Path(__file__).resolve().parents[1]
TEST_HOST = os.getenv("TEST_DB_HOST", "localhost")
TEST_PORT = os.getenv("TEST_DB_PORT", "55432")
TEST_DATABASE = os.getenv("TEST_DB_NAME", "ons_edp_test")
TEST_ADMIN_USER = os.getenv("TEST_DB_ADMIN_USER", "postgres")
TEST_ADMIN_PASSWORD = os.getenv("TEST_DB_ADMIN_PASSWORD", "test_admin_password")
TEST_ETL_USER = os.getenv("TEST_DB_USER", "etl_test")
TEST_ETL_PASSWORD = os.getenv("TEST_DB_PASSWORD", "test_etl_password")
TEST_OLTP_USER = os.getenv("TEST_OLTP_USER", "oltp_test")
TEST_OLTP_PASSWORD = os.getenv("TEST_OLTP_PASSWORD", "test_oltp_password")


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--run-integration",
        action="store_true",
        default=False,
        help="run tests that require compose.test.yaml PostgreSQL",
    )
    parser.addoption(
        "--run-e2e",
        action="store_true",
        default=False,
        help="run the complete empty-database pipeline and rerun scenario",
    )


def pytest_collection_modifyitems(
    config: pytest.Config, items: list[pytest.Item]
) -> None:
    run_integration = config.getoption("--run-integration")
    run_e2e = config.getoption("--run-e2e")
    for item in items:
        if "e2e" in item.keywords and not run_e2e:
            item.add_marker(pytest.mark.skip(reason="use --run-e2e"))
        elif (
            "integration" in item.keywords or "data_quality" in item.keywords
        ) and not (run_integration or run_e2e):
            item.add_marker(pytest.mark.skip(reason="use --run-integration"))


@dataclass(frozen=True)
class TestDatabase:
    host: str = TEST_HOST
    port: str = TEST_PORT
    database: str = TEST_DATABASE

    def dsn(self, user: str, password: str) -> str:
        return (
            f"host={self.host} port={self.port} dbname={self.database} "
            f"user={user} password={password} connect_timeout=3"
        )

    def sqlalchemy_url(self, user: str, password: str) -> str:
        return (
            f"postgresql+psycopg2://{user}:{password}@"
            f"{self.host}:{self.port}/{self.database}"
        )

    def environment(self, *, oltp: bool = False) -> dict[str, str]:
        return {
            "DB_HOST": self.host,
            "DB_PORT": self.port,
            "DB_NAME": self.database,
            "DB_USER": TEST_OLTP_USER if oltp else TEST_ETL_USER,
            "DB_PASSWORD": TEST_OLTP_PASSWORD if oltp else TEST_ETL_PASSWORD,
            "GALAXY_START_DATE": "2026-07-01",
            "GALAXY_END_DATE": "2026-07-03",
            "LOG_LEVEL": "WARNING",
        }


@pytest.fixture(scope="session")
def test_database(request: pytest.FixtureRequest) -> TestDatabase:
    if not (
        request.config.getoption("--run-integration")
        or request.config.getoption("--run-e2e")
    ):
        pytest.skip("isolated PostgreSQL was not requested")
    database = TestDatabase()
    try:
        with psycopg2.connect(
            database.dsn(TEST_ADMIN_USER, TEST_ADMIN_PASSWORD)
        ) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT current_database(), version()")
                current_database, version = cursor.fetchone()
    except psycopg2.Error as exc:
        pytest.fail(
            "isolated PostgreSQL is unavailable; start compose.test.yaml "
            f"before running integration tests: {exc}",
            pytrace=False,
        )
    assert current_database == TEST_DATABASE
    assert "PostgreSQL 17" in version
    return database


@pytest.fixture
def admin_connection(test_database: TestDatabase) -> Iterator[psycopg2.extensions.connection]:
    connection = psycopg2.connect(
        test_database.dsn(TEST_ADMIN_USER, TEST_ADMIN_PASSWORD)
    )
    try:
        yield connection
    finally:
        connection.close()


@pytest.fixture
def etl_engine(test_database: TestDatabase) -> Iterator[Engine]:
    engine = create_engine(
        test_database.sqlalchemy_url(TEST_ETL_USER, TEST_ETL_PASSWORD),
        pool_pre_ping=True,
    )
    try:
        yield engine
    finally:
        engine.dispose()


@pytest.fixture
def reset_database(
    admin_connection: psycopg2.extensions.connection,
) -> Callable[[], None]:
    def reset() -> None:
        with admin_connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT format('%I.%I', schemaname, tablename)
                FROM pg_tables
                WHERE schemaname IN ('oltp', 'data_vault', 'galaxy', 'etl')
                  AND NOT (
                      schemaname = 'galaxy' AND tablename = 'dim_junk_flags'
                  )
                ORDER BY schemaname, tablename
                """
            )
            tables = [row[0] for row in cursor.fetchall()]
            if tables:
                cursor.execute(
                    "TRUNCATE TABLE " + ", ".join(tables) + " RESTART IDENTITY CASCADE"
                )
        admin_connection.commit()

    return reset


@pytest.fixture
def run_stage(test_database: TestDatabase) -> Callable[..., subprocess.CompletedProcess[str]]:
    def run(
        command: list[str],
        *,
        oltp: bool = False,
        environment: dict[str, str] | None = None,
        timeout: int = 180,
    ) -> subprocess.CompletedProcess[str]:
        stage_environment = os.environ.copy()
        stage_environment.update(test_database.environment(oltp=oltp))
        if environment:
            stage_environment.update(environment)
        return subprocess.run(
            command,
            cwd=PROJECT_ROOT,
            env=stage_environment,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    return run


@pytest.fixture
def run_seed(run_stage: Callable[..., subprocess.CompletedProcess[str]]):
    return lambda **kwargs: run_stage(
        [sys.executable, "DDL/populate.py"], oltp=True, **kwargs
    )


@pytest.fixture
def run_vault(run_stage: Callable[..., subprocess.CompletedProcess[str]]):
    return lambda **kwargs: run_stage(
        [sys.executable, "-m", "ETL.data_vault.main"], **kwargs
    )


@pytest.fixture
def run_galaxy(run_stage: Callable[..., subprocess.CompletedProcess[str]]):
    return lambda **kwargs: run_stage(
        [
            sys.executable,
            "-m",
            "ETL.galaxy.main",
            "--start-date",
            "2026-07-01",
            "--end-date",
            "2026-07-03",
        ],
        **kwargs,
    )


@pytest.fixture
def loaded_pipeline(
    reset_database: Callable[[], None],
    run_seed,
    run_vault,
    run_galaxy,
) -> None:
    reset_database()
    for name, result in (
        ("seed", run_seed()),
        ("Data Vault", run_vault()),
        ("Galaxy", run_galaxy()),
    ):
        assert result.returncode == 0, (
            f"{name} failed\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
