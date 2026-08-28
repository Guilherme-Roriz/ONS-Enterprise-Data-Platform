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
- Apache Airflow 3
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
- Scheduled Airflow DAG with retries, timeouts, and Asset lineage

## Documentation

Detailed technical documentation, architecture diagrams, data models, and implementation decisions are available in the **`/docs`** directory.

ETL operating guides:

- [`ETL/1ETL.md`](ETL/1ETL.md) — OLTP → Data Vault
- [`ETL/2ETL.md`](ETL/2ETL.md) — Data Vault → Galaxy
- [`docs/airflow.md`](docs/airflow.md) — Airflow architecture and local operation

Install the Python dependencies with `pip install -r requirements.txt` and copy `.env.example` to `.env`.

Run the ETL stages in order:

```bash
python -m ETL.data_vault.main
python -m ETL.galaxy.main
```

## Docker

The local Docker stack runs PostgreSQL and Airflow. The DAG follows the same
path as the data:

```text
seed_oltp → load_data_vault → publish_galaxy
```

Airflow uses a separate metadata database and `LocalExecutor`. The API server,
scheduler, and DAG processor run as separate Airflow 3 services. The scheduler
executes the existing Python entry points from a custom image; ETL rules are not
duplicated in the DAG.

To try it, copy `.env.example` to `.env`, change the example passwords, and
generate `AIRFLOW_FERNET_KEY` and `AIRFLOW_API_JWT_SECRET`. The exact commands,
generated login, health checks, and DAG walkthrough are in
[`docs/airflow.md`](docs/airflow.md).

Then run:

```bash
docker compose config --quiet
docker compose up --build airflow-init
docker compose up -d
```

The original container-only sequence remains available through the `manual`
profile:

```bash
docker compose --profile manual up --build \
  seed-oltp oltp-to-vault vault-to-galaxy
```

On its first start, PostgreSQL creates the schemas and the separate users used
by the data generator and ETLs. The databases and runtime logs live in named
volumes, so stopping the containers does not delete them.

I have not run the stack locally yet because Docker is not installed on the
current machine. The configuration and Python code have been checked, but the
first Airflow image build and end-to-end DAG run are still pending.

The commands, environment variables, reset instructions, and network image are
in [`docs/docker.md`](docs/docker.md).

## Project Status

🚧 In development

This project is being developed incrementally as part of a continuous learning journey in Data Engineering and Analytics Engineering.

---

## License

Licensed under the MIT License.
