# ONS Enterprise Data Platform

The ONS Enterprise Data Platform is an end-to-end Data Engineering portfolio
project inspired by the Brazilian National Electric System Operator.

It generates synthetic power-grid data and moves it through three PostgreSQL
layers:

```text
Operational model (OLTP) -> Data Vault 2.0 -> Galaxy dimensional model
```

The project demonstrates relational and dimensional modeling, configuration-
driven ETL, idempotent loads, least-privilege database roles, containerized
infrastructure, and Airflow orchestration.

## Current architecture

```text
Docker Compose
  -> project PostgreSQL
  -> separate Airflow metadata PostgreSQL
  -> Airflow API server, scheduler, and DAG processor

Airflow DAG
  -> DockerOperator
  -> one ons-etl:local container per stage
  -> ons-network
  -> postgres:5432
```

Compose owns the local infrastructure. Airflow owns scheduling, retries,
timeouts, task history, and Asset lineage. `DockerOperator` runs the existing
project entry points in isolated containers:

```text
seed_oltp         -> python DDL/populate.py
load_data_vault   -> python -m ETL.data_vault.main
publish_galaxy    -> python -m ETL.galaxy.main
```

The Airflow image contains only the DAG and its Docker provider. ETL code and
dependencies live in the reusable `ons-etl:local` image.

## Technologies

- PostgreSQL 17
- Python 3.13
- SQL
- Docker and Docker Compose
- Apache Airflow 3.3.1
- Data Vault 2.0
- Kimball dimensional modeling

## Main features

- deterministic synthetic operational data;
- separate non-superuser roles for OLTP loading and ETL;
- configuration-driven OLTP -> Data Vault ingestion;
- idempotent Data Vault -> Galaxy publishing with SCD2 resolution;
- automatic PostgreSQL schema and role initialization;
- separate project and Airflow metadata databases;
- scheduled DAG with retries, execution timeouts, a DAG timeout, and one active
  run at a time;
- Asset lineage from OLTP to Data Vault to Galaxy;
- workload isolation through `DockerOperator`;
- legacy Compose-only execution available only through the `manual` profile.

No Redis or Celery components are used by the local stack.

## Documentation

- [Airflow architecture and operations](docs/airflow.md)
- [Docker and local infrastructure](docs/docker.md)
- [Testing and Data Quality](docs/testing.md)
- [OLTP model](docs/oltp.md)
- [Data Vault model](docs/data_vault.md)
- [Kimball/Galaxy model](docs/kimball.md)
- [OLTP -> Data Vault ETL](ETL/1ETL.md)
- [Data Vault -> Galaxy ETL](ETL/2ETL.md)

## Local start

Copy `.env.example` to `.env`, replace all placeholder passwords, and
generate independent values for:

- `AIRFLOW_FERNET_KEY`
- `AIRFLOW_API_SECRET_KEY`
- `AIRFLOW_API_JWT_SECRET`

The exact generation commands and Linux Docker socket setup are in
[`docs/airflow.md`](docs/airflow.md#environment-variables-and-secrets).

Then validate, build, migrate, and start:

```bash
docker compose config --quiet
docker compose --profile manual build seed-oltp
docker compose build airflow-init
docker compose up airflow-init
docker compose up -d
docker compose ps --all
```

Open `http://localhost:8080`, inspect
`ons_enterprise_data_pipeline`, unpause it, and trigger a manual run. New DAGs
start paused by design.

Confirm that the DAG has no import errors:

```bash
docker compose exec airflow-scheduler airflow dags list-import-errors --output json
```

## Manual Compose flow

The older Compose-only sequence is inactive during a normal start. Run it
explicitly only while the Airflow DAG is paused and has no active run:

```bash
docker compose --profile manual up --build \
  seed-oltp oltp-to-vault vault-to-galaxy
```

## Repository tests

The pytest suite separates fast unit contracts from real PostgreSQL integration,
Data Quality and E2E validation:

```bash
python -m pip install -r requirements-test.txt
python -m pytest -m unit -q
```

The isolated PostgreSQL 17 suite runs automatically in GitHub Actions without
reusing the development database. The verified run passed 37 unit tests and 13
PostgreSQL Integration/Data Quality/E2E tests, including a complete idempotent
rerun. The Airflow scheduler/DockerOperator E2E also passed: an automatic daily
run and a manual rerun completed with all tasks successful, correct dependency
order, Data Quality assertions and matching snapshots. Evidence is available in
[GitHub Actions #9](https://github.com/Guilherme-Roriz/ONS-Enterprise-Data-Platform/actions/runs/34882377677).
See [Testing and Data Quality](docs/testing.md)
for the environment, markers, fixtures, commands, failure paths, evidence and
explicit limitations.

## Project status

In development. The project is built incrementally as a Data Engineering and
Analytics Engineering learning portfolio.

## License

Licensed under the MIT License.
