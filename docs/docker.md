# Running the project with Docker

Docker Compose provides the local infrastructure: two PostgreSQL databases,
the Airflow services, volumes, health checks, and the shared `ons-network`.
Airflow then uses `DockerOperator` to create one short-lived
`ons-etl:local` container for each pipeline stage.

```text
Compose infrastructure
  postgres
  airflow-db
  airflow-api-server
  airflow-scheduler
  airflow-dag-processor
        |
        +-- DockerOperator --> ons-etl:local --> postgres:5432
```

The complete orchestration, socket security, failure behavior, and operating
guide are in [`airflow.md`](airflow.md).

## Images and services

The root `Dockerfile` builds `ons-etl:local`. That image contains the Python
dependencies, `DDL/`, and `ETL/`. The same image runs all three commands:

```text
python DDL/populate.py
python -m ETL.data_vault.main
python -m ETL.galaxy.main
```

`Dockerfile.airflow` builds `ons-airflow:3.3.1`. It contains the DAG and the
pinned Docker provider, not the ETL implementation.

Compose starts these services by default:

- `postgres`: project OLTP, Data Vault, and Galaxy data;
- `airflow-db`: Airflow metadata only, with no host port;
- `airflow-init`: one-off metadata migration;
- `airflow-api-server`: UI and API on port 8080 by default;
- `airflow-scheduler`: task scheduling and Docker API access;
- `airflow-dag-processor`: DAG parsing.

`seed-oltp`, `oltp-to-vault`, and `vault-to-galaxy` are disabled by
default. They exist only in the `manual` profile for comparing the older
Compose-only execution path.

## First run

Copy `.env.example` to `.env`, change every placeholder password, and
generate the three independent Airflow secrets described in
[`airflow.md`](airflow.md#environment-variables-and-secrets).

Validate and build:

```bash
docker compose config --quiet
docker compose --profile manual build seed-oltp
docker compose build airflow-init
```

The first build creates `ons-etl:local`; it does not start the manual
pipeline. The second creates the Airflow image.

Migrate the Airflow metadata database and start the stack:

```bash
docker compose up airflow-init
docker compose up -d
docker compose ps --all
```

After the services become healthy, inspect and run
`ons_enterprise_data_pipeline` at `http://localhost:8080`. New DAGs start
paused.

## Database initialization

The first time `postgres` starts with an empty `postgres-data` volume, it
runs `docker/postgres/init/10-bootstrap.sh`. The script creates the project
roles, applies the DDL, and grants each role only the permissions needed by its
workload.

The DDL order is:

1. `DDL/oltp.sql`
2. `DDL/datavault.sql`
3. `DDL/fact_constelation.sql`
4. `DDL/etl.sql`

This bootstrap runs only against an empty data volume. Restarting PostgreSQL
does not reapply changed DDL to an existing database.

Host-side Python connects to `localhost` and the published
`POSTGRES_PORT`. Containers use the Compose DNS name `postgres` and the
internal port `5432`.

## Manual profile

Run the old sequence only when the Airflow DAG is paused and has no active run:

```bash
docker compose --profile manual up --build \
  seed-oltp oltp-to-vault vault-to-galaxy
```

Compose waits for PostgreSQL to become healthy and for each previous one-off
container to finish successfully. Those job containers ending as
`Exited (0)` is expected.

The profile prevents accidental competition during a normal
`docker compose up`; explicitly starting the manual path and Airflow together
can still make both write to the project database.

## Stop and reset

Stop containers while keeping databases and logs:

```bash
docker compose down
```

Delete all named volumes and return to an empty environment:

```bash
docker compose down --volumes
```

The reset is destructive: it removes both databases, Airflow metadata and task
logs, ETL logs, and the generated development login.

## Files involved

- `Dockerfile`: reusable `ons-etl:local` workload image;
- `Dockerfile.airflow`: orchestration-only Airflow image;
- `compose.yaml`: infrastructure, networks, volumes, health checks, and
  profiles;
- `.env.example`: documented local configuration without real secrets;
- `docker/postgres/init/10-bootstrap.sh`: first-start database bootstrap;
- `airflow/dags/ons_enterprise_pipeline.py`: DockerOperator task definitions;
- `airflow/requirements.txt`: pinned Docker provider.
