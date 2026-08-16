# ONS Enterprise Data Platform

## Overview

The **ONS Enterprise Data Platform** is an end-to-end Data Engineering portfolio project inspired by the Brazilian National Electric System Operator (ONS).

The project simulates operational data from an electrical power grid and demonstrates how enterprise data flows through a modern analytics platform—from transactional systems to a dimensional data warehouse.

Its primary goal is to showcase industry-standard data engineering practices, including data modeling, ETL development, data warehousing, and analytical data preparation using a realistic business domain.

## Architecture

The platform follows a modern enterprise data architecture:

> Synthetic Data Sources → Operational Database (OLTP) & Data Lake → Data Vault → Analytics & Business Intelligence

For a detailed architecture diagram, see the documentation in `/docs`.

## Technologies

- PostgreSQL
- SQL
- Python
- Docker & Docker Compose
- Data Vault 2.0
- Kimball Dimensional Modeling
- Git & GitHub

## Features

- Synthetic power system data generation
- Enterprise data modeling
- ETL / ELT pipelines
- Data Warehouse implementation
- Dimensional modeling
- Business-oriented analytical datasets
- End-to-end project documentation
- Complete configuration-driven OLTP → Data Vault ingestion
- Idempotent Data Vault → Galaxy dimensional ETL with SCD2 resolution
- Containerized PostgreSQL with automated schema and role initialization
- Shared Python image with end-to-end pipeline orchestration

## Documentation

Detailed technical documentation, architecture diagrams, data models, and implementation decisions are available in the **`/docs`** directory.

ETL operating guides:

- [`ETL/1ETL.md`](ETL/1ETL.md) — OLTP → Data Vault
- [`ETL/2ETL.md`](ETL/2ETL.md) — Data Vault → Galaxy

Install the Python dependencies with `pip install -r requirements.txt` and copy `.env.example` to `.env`.

Run the ETL stages in order:

```bash
python -m ETL.data_vault.main
python -m ETL.galaxy.main
```

## Containerized Pipeline

Docker Compose provisions PostgreSQL and runs the synthetic data generator and
both ETL stages in sequence:

```text
postgres → seed-oltp → oltp-to-vault → vault-to-galaxy
```

The three Python jobs use the same `ons-etl:local` image. PostgreSQL must become
healthy before data generation starts, and each downstream job waits for the
previous stage to complete successfully. Named volumes preserve the database
and ETL logs across container recreation.

Create a local `.env` from `.env.example`, replace the placeholder credentials,
and then run:

```bash
docker compose config --quiet
docker compose up --build -d
docker compose logs -f seed-oltp oltp-to-vault vault-to-galaxy
```

On the first start of an empty database volume, the PostgreSQL bootstrap creates
the project schemas and separate non-superuser roles for OLTP loading and ETL.

> The Docker configuration has been statically validated. Image build and
> end-to-end runtime validation are still pending.

See [`docs/docker.md`](docs/docker.md) for configuration, operating commands,
security boundaries, persistence behavior, and troubleshooting.

## Project Status

🚧 In development

This project is being developed incrementally as part of a continuous learning journey in Data Engineering and Analytics Engineering.

---

## License

Licensed under the MIT License.
