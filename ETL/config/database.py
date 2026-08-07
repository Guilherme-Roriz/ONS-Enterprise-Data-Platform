"""Database connection factory shared by both ETL stages."""

from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import quote_plus

from dotenv import load_dotenv
from sqlalchemy import Engine, create_engine

PROJECT_ROOT = Path(__file__).resolve().parents[2]

# An explicit ENV_FILE wins. Otherwise use the conventional project-root .env.
env_file = Path(os.environ.get("ENV_FILE", PROJECT_ROOT / ".env"))
load_dotenv(env_file, override=False)


def get_database_url() -> str:
    """Build a PostgreSQL SQLAlchemy URL from environment variables."""
    explicit_url = os.getenv("DATABASE_URL")
    if explicit_url:
        return explicit_url

    host = os.getenv("DB_HOST") or "localhost"
    port = os.getenv("DB_PORT") or "5432"
    database = os.getenv("DB_NAME") or "ons_edp"
    user = os.getenv("DB_USER") or "etl_user"
    password = quote_plus(os.getenv("DB_PASSWORD", ""))
    return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{database}"


def get_engine() -> Engine:
    """Create a resilient SQLAlchemy engine for PostgreSQL."""
    return create_engine(get_database_url(), pool_pre_ping=True, echo=False)
