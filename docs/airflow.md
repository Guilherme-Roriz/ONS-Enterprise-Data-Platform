# Orchestrating the project with Airflow

Airflow does not replace the ETL code in this project. Its job is to decide
when each stage runs, keep the stages in the right order, retry transient
failures, and leave an execution history we can inspect later.

The DAG follows the same path we already had in Docker:

```text
seed_oltp -> load_data_vault -> publish_galaxy
```

The important difference is that these are now Airflow tasks. The scheduler
owns their state instead of Compose starting three one-off containers in a
fixed sequence.

## The local architecture

```text
                         +--------------------+
Browser :8080 ---------->| Airflow API server |
                         +---------+----------+
                                   |
                         +---------v----------+
                         | Airflow metadata DB|
                         +----+-----------+---+
                              ^           ^
                              |           |
                    +---------+--+   +----+-------------+
                    | scheduler  |   | DAG processor    |
                    | LocalExecutor|  | parses DAG files |
                    +------+-----+   +------------------+
                           |
              seed -> Data Vault -> Galaxy
                           |
                    +------v------+
                    | project DB  |
                    +-------------+
```

There are two PostgreSQL containers on purpose. `postgres` holds the project
data. `airflow-db` holds scheduling state, task history, and other Airflow
metadata. Mixing those concerns would make backups, permissions, and future
migrations harder than they need to be.

This stack uses `LocalExecutor`. Tasks run from the scheduler container, so a
Redis broker and separate Celery workers would only add moving parts right now.
The API server, scheduler, and DAG processor are separate because Airflow 3
requires that service-oriented layout even for a small installation.

## Decisions worth noticing

The image is pinned to Airflow 3.3.1 and Python 3.13. The DAG imports `Asset`,
`dag`, and `task` from `airflow.sdk`, which is the public authoring API in
Airflow 3. The standard provider is pinned separately because providers have
their own release cycle.

The custom image contains the existing `DDL` and `ETL` directories. Airflow
calls their entry points; it does not contain a second implementation of the
business rules.

The DAG publishes three Assets:

- `ons://postgres/oltp`
- `ons://postgres/data-vault`
- `ons://postgres/galaxy`

An Asset event is emitted only after its task succeeds. This gives us a small
lineage view in the Airflow UI without adding another catalog tool.

The schedule is `06:00` every day in `America/Sao_Paulo`. Catchup is disabled,
only one DAG run can be active, and new DAGs start paused. Nothing runs on a new
machine until we inspect the DAG and enable it or trigger it manually.

Retries are useful only because all three stages are safe to run again. The
synthetic seed uses stable business keys and conflict handling, while both ETLs
already use idempotent loads. Airflow retries would be dangerous if a rerun
silently duplicated data.

## Files to review

I would read the implementation in this order:

1. `.env.example` — separates configuration from code and shows which values
   are secrets.
2. `Dockerfile.airflow` — extends the official image and packages this project.
3. `airflow/requirements.txt` — pins the provider independently from Airflow.
4. `airflow/scripts/run_pipeline_stage.sh` — maps each task to the correct
   database role and existing Python entry point.
5. `airflow/dags/ons_enterprise_pipeline.py` — defines scheduling, retries,
   timeouts, dependencies, and Assets.
6. `compose.yaml` — connects the Airflow components and both databases.
7. `tests/test_airflow_orchestration.py` — protects the architecture from
   accidental regressions.

That order moves from configuration to runtime and finally to orchestration.
It also keeps the DAG easier to read because the container details are already
familiar by the time we reach it.

## Preparing `.env`

Copy the example file from the repository root:

```powershell
Copy-Item .env.example .env
```

Using Bash:

```bash
cp .env.example .env
```

Replace every example database password. Keep the Airflow metadata password
URL-safe because it becomes part of a SQLAlchemy connection URL; letters,
numbers, hyphens, and underscores are safe choices.

Generate a Fernet key with Python:

```bash
python -c "import base64,secrets; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())"
```

Put the result in `AIRFLOW_FERNET_KEY`. Airflow uses this shared key to encrypt
sensitive values stored in its metadata database.

Generate the API JWT secret separately:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Put that result in `AIRFLOW_API_JWT_SECRET`. Do not reuse a database password
for either secret, and never commit `.env`.

On Linux, set `AIRFLOW_UID` to the result of `id -u` if you change the named
volumes to bind mounts later. The default `50000` is correct for Docker Desktop
and the official Airflow image used here.

## First start

Validate the resolved Compose configuration before creating containers:

```bash
docker compose config --quiet
```

Build the images and apply the Airflow metadata migrations:

```bash
docker compose up --build airflow-init
```

`airflow-init` should exit with code `0`. It is a one-off migration job, so an
exited container is expected.

Start the long-running services:

```bash
docker compose up -d
docker compose ps --all
```

The two databases, API server, scheduler, and DAG processor should become
healthy. Airflow's official local setup needs at least 4 GB of memory available
to Docker; 8 GB is more comfortable.

The development login is `admin`. The Simple Auth Manager generates its
password on first start and writes it to the API server logs:

```bash
docker compose logs airflow-api-server
```

The password file is kept in the `airflow-auth` volume, so the password does
not change every time the container restarts. Open `http://localhost:8080`, log
in, inspect `ons_enterprise_data_pipeline`, and then trigger it manually.

## Following a run

The graph should show this order:

```text
seed_oltp
    |
load_data_vault
    |
publish_galaxy
```

Airflow captures each task's output separately. The scheduler log is still
useful when a task cannot even start:

```bash
docker compose logs -f airflow-scheduler
```

The task timeouts are deliberately wider than a normal local run:

- 20 minutes for the synthetic seed;
- 40 minutes for the Data Vault load;
- 40 minutes for the Galaxy load;
- 2 hours for the complete DAG run.

A task gets two retries with a two-minute delay. A final failure stops the DAG
immediately, and downstream tasks do not run with incomplete data.

## Keeping the old Docker path

The original one-container-per-stage flow is still available for comparison.
It now lives behind the `manual` Compose profile so it does not race against
Airflow:

```bash
docker compose --profile manual up --build \
  seed-oltp oltp-to-vault vault-to-galaxy
```

This is useful while learning: Compose expresses container startup order,
whereas Airflow records task runs, retries, scheduling, lineage, and operational
history.

## Stopping and resetting

Stop the stack while keeping both databases, logs, and the generated login:

```bash
docker compose down
```

Start it again with `docker compose up -d`.

To remove every named volume and start from zero:

```bash
docker compose down --volumes
```

That command permanently deletes the project database, Airflow metadata,
Airflow task logs, ETL logs, and the generated login. Use it only when a full
local reset is intentional.

## Useful checks

List the DAGs parsed by Airflow:

```bash
docker compose exec airflow-scheduler airflow dags list
```

Show DAG import errors:

```bash
docker compose exec airflow-scheduler airflow dags list-import-errors
```

If a Python, DAG, requirement, or Dockerfile change is not visible, rebuild the
custom image:

```bash
docker compose up --build -d
```

The repository tests do not need a running Airflow installation. They parse the
DAG and Compose configuration and check the decisions described above:

```bash
python -m unittest discover -s tests -v
```

The final integration check still needs Docker: build the image, confirm there
are no import errors, and complete one DAG run from OLTP through Galaxy.

## Where this stops being production-ready

This is a serious local learning environment, not a production deployment.
The Simple Auth Manager is meant for development, LocalExecutor runs on one
host, secrets live in a local `.env`, and named volumes are not a backup plan.

A production version would need a production auth manager, a managed secrets
store, tested backups, monitoring and alerting, remote log storage, and an
executor or platform sized for the expected workload. The current design keeps
those future changes possible without pretending they are already implemented.

The version and component choices follow the official Airflow documentation:

- [Running Airflow in Docker](https://airflow.apache.org/docs/apache-airflow/3.3.1/howto/docker-compose/index.html)
- [Airflow 3 architecture](https://airflow.apache.org/docs/apache-airflow/3.3.1/core-concepts/overview.html)
- [Simple Auth Manager](https://airflow.apache.org/docs/apache-airflow/3.3.1/core-concepts/auth-manager/simple/index.html)
- [Building the official image](https://airflow.apache.org/docs/docker-stack/build.html)
