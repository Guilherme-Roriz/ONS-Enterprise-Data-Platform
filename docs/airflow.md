# Orchestrating the project with Airflow

The responsibility boundary is deliberately simple:

```text
Docker Compose  -> local infrastructure
Airflow         -> orchestration and execution history
DockerOperator  -> containers created from ons-etl:local
```

Airflow does not contain or import the project ETL. It schedules each stage,
asks the Docker Engine to create a workload container, follows its result, and
records the run.

## Architecture

```text
Browser :8080
     |
     v
Airflow API server ----------------------+
     |                                   |
     v                                   v
airflow-db                         airflow-scheduler
(Airflow metadata only)            (LocalExecutor)
                                         |
                                  /var/run/docker.sock
                                         |
                                         v
                                  Docker Engine / API
                                         |
                +------------------------+------------------------+
                |                        |                        |
                v                        v                        v
          seed_oltp                load_data_vault          publish_galaxy
          ons-etl:local            ons-etl:local            ons-etl:local
                |                        |                        |
                +------------------------+------------------------+
                                         |
                                    ons-network
                                         |
                                         v
                                postgres:5432 / ons_edp
```

The DAG processor only parses the DAG. The API server serves the UI and API.
The scheduler owns task state and runs `DockerOperator` through
`LocalExecutor`. The Python workloads themselves run in sibling containers,
not in the scheduler.

There are two PostgreSQL containers on purpose:

- `postgres` stores the project's OLTP, Data Vault, and Galaxy data;
- `airflow-db` stores DAG runs, task instances, and other Airflow metadata.

No Redis, Celery broker, or Airflow worker is needed for this local design.

## Task flow and lineage

| Task | Command inside `ons-etl:local` | Database role | Asset emitted |
|---|---|---|---|
| `seed_oltp` | `python DDL/populate.py` | `OLTP_USER` | `ons://postgres/oltp` |
| `load_data_vault` | `python -m ETL.data_vault.main` | `DB_USER` | `ons://postgres/data-vault` |
| `publish_galaxy` | `python -m ETL.galaxy.main` | `DB_USER` | `ons://postgres/galaxy` |

The dependency chain is:

```text
seed_oltp -> load_data_vault -> publish_galaxy
   OLTP          Data Vault          Galaxy
```

An Asset event is emitted only after its task succeeds. The graph therefore
describes both execution order and the data lineage OLTP -> Data Vault ->
Galaxy.

The schedule is 06:00 daily in `America/Sao_Paulo`. Catchup is disabled, only
one DAG run can be active, and new DAGs start paused. A new local environment
does not execute the pipeline until someone reviews and enables the DAG.

## What is inside each image

`ons-etl:local` is built from the root `Dockerfile`. It contains the project
dependencies, `DDL/`, and `ETL/`.

`ons-airflow:3.3.1` is built from `Dockerfile.airflow`. It contains the DAG
and the pinned Docker provider. It does not copy `DDL/`, `ETL/`, the project
requirements, or an intermediate shell runner.

This is the key architectural rule: changing ETL code requires rebuilding
`ons-etl:local`; Airflow only needs a rebuild when its DAG, provider, or
Airflow image changes.

## Docker networking

Compose gives the bridge network the explicit engine-level name
`ons-network`. Every Airflow component and both databases join that network.
Each `DockerOperator` also sets `network_mode="ons-network"`, so its
short-lived container can resolve the project database at `postgres:5432`.

`localhost` would be wrong inside a workload container: there it refers to
that workload container itself. `DOCKER_DB_HOST` should therefore stay
`postgres` for the Compose stack.

## Docker socket and API

Only `airflow-scheduler` mounts:

```text
/var/run/docker.sock:/var/run/docker.sock
```

`DockerOperator` connects to `unix://var/run/docker.sock`. It is controlling
the host Docker Engine through its API; it is not starting Docker inside
Airflow.

`mount_tmp_dir=False` is intentional. The operator does not try to mount a
temporary scheduler path into a sibling container, a path the Docker Engine
may not be able to see. The workloads do not need that temporary mount.

On Linux, the Airflow user may need the socket's group ID. Set `DOCKER_GID`
in `.env` to:

```bash
stat -c '%g' /var/run/docker.sock
```

Docker Desktop normally works with the default `DOCKER_GID=0`.

The Docker socket is a major security boundary. A process that can control it
can create privileged containers and effectively control the host. This direct
mount is acceptable only for this trusted local learning environment. A
production deployment should use a more isolated runtime or a tightly
restricted and protected Docker API instead of copying this setup unchanged.

## Environment variables and secrets

Copy the example file:

```powershell
Copy-Item .env.example .env
```

Using Bash:

```bash
cp .env.example .env
```

Replace every placeholder password. Use URL- and JSON-safe local passwords
(letters, numbers, hyphens, and underscores are uncomplicated choices), because
the metadata connection is a URL and the project Airflow Connections are JSON.
Never commit `.env`.

Generate three independent Airflow secrets:

```bash
python -c "import base64,secrets; print(base64.urlsafe_b64encode(secrets.token_bytes(32)).decode())"
python -c "import secrets; print(secrets.token_urlsafe(48))"
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Store the outputs, in order, as:

1. `AIRFLOW_FERNET_KEY`
2. `AIRFLOW_API_SECRET_KEY`
3. `AIRFLOW_API_JWT_SECRET`

Do not reuse one value for the three settings.

| Configuration | Where it is available | Purpose |
|---|---|---|
| `POSTGRES_ADMIN_*` | project PostgreSQL initialization | Creates database roles and schemas; never reaches workload containers |
| `OLTP_USER/PASSWORD` | `postgres`, scheduler Connection `ons_oltp`, then `seed_oltp` | Least-privilege OLTP fixture load |
| `DB_USER/PASSWORD` | `postgres`, scheduler Connection `ons_etl`, then the two ETLs | Data Vault and Galaxy loads |
| `AIRFLOW_DB_*` | Airflow components and `airflow-db` | Airflow metadata only |
| `AIRFLOW_FERNET_KEY` | Airflow components | Encrypts supported metadata fields at rest |
| `AIRFLOW_API_SECRET_KEY` | API server and scheduler | API/log-token signing |
| `AIRFLOW_API_JWT_SECRET` | API server and scheduler | Shared Airflow 3 task/API identity signing |
| `GALAXY_START_DATE/END_DATE`, `LOG_LEVEL` | scheduler, then Galaxy workload | Galaxy runtime options |

The scheduler receives the project credentials as environment-defined Airflow
Connections. The DAG renders those values into the workload environment:

- `seed_oltp` gets only the five database fields from `ons_oltp`;
- `load_data_vault` gets only the five database fields from `ons_etl`;
- `publish_galaxy` gets the ETL database fields plus its date range and log
  level.

Airflow metadata credentials are never passed to `ons-etl:local`. The OLTP
password is never passed to either ETL. The ETL password is never passed to the
seed task.

## First start

From the repository root, validate the resolved configuration:

```bash
docker compose config --quiet
```

Build both custom images. The `manual` profile is named here only so Compose
can target its image; it does not start the old pipeline:

```bash
docker compose --profile manual build seed-oltp
docker compose build airflow-init
```

Apply the Airflow metadata migrations:

```bash
docker compose up airflow-init
```

`airflow-init` should exit with code 0. Start the long-running infrastructure:

```bash
docker compose up -d
docker compose ps --all
```

Expected state:

- `postgres` and `airflow-db` are healthy;
- the API server, scheduler, and DAG processor are healthy;
- `airflow-init` is exited with code 0;
- none of the three `manual` services is running.

Confirm that Airflow parsed the DAG:

```bash
docker compose exec airflow-scheduler airflow dags list
docker compose exec airflow-scheduler airflow dags list-import-errors --output json
```

The second command should return an empty JSON list.

## Triggering and following a run

The development user is `admin`. Simple Auth Manager generates its password
on first start:

```bash
docker compose logs airflow-api-server
```

Open `http://localhost:8080`. Review
`ons_enterprise_data_pipeline`, unpause it, and trigger it manually.

The equivalent local CLI commands are:

```bash
docker compose exec airflow-scheduler airflow dags unpause ons_enterprise_data_pipeline
docker compose exec airflow-scheduler airflow dags trigger ons_enterprise_data_pipeline
docker compose exec airflow-scheduler airflow dags list-runs ons_enterprise_data_pipeline
```

A trigger submitted while the DAG is paused stays queued, so unpause it first.

Airflow task logs are the primary run record. `DockerOperator` streams each
container's stdout and stderr into its task log. Successful workload containers
are removed automatically; failed ones are retained for diagnosis.

Useful host checks:

```bash
docker compose logs -f airflow-scheduler
docker ps -a --filter label=ons.pipeline=ons_enterprise_data_pipeline
docker logs <failed-container-id>
```

The last command requires the exact ID of a failed workload container.

## Retries, timeouts, and failure paths

Every task gets two retries with a two-minute delay. The seed task has a
20-minute execution timeout; each ETL has 40 minutes. The complete DAG has a
two-hour timeout, and only one run can be active.

The stages are idempotent, which makes retries safe. After the final failed
attempt, downstream tasks do not start and no downstream Asset event is
emitted.

| Failure | Observable result | First check |
|---|---|---|
| `ons-etl:local` was not built | Docker cannot create/pull the workload image; task retries | `docker image inspect ons-etl:local` |
| Scheduler cannot access the socket | Permission or connection error before the workload starts | socket mount and `DOCKER_GID` |
| `ons-network` is missing | container creation/network attachment fails | `docker network inspect ons-network` |
| `postgres` is unavailable | database connection failure inside the task | `docker compose ps postgres` |
| Wrong OLTP or ETL credentials | PostgreSQL authentication or permission error | matching role/password in `.env` |
| Workload exits nonzero | task fails, retries, failed container remains | task log, then `docker logs` |
| Task exceeds its timeout | Airflow stops the attempt and applies retry policy | task duration and workload log |
| API/JWT keys differ or clocks drift | execution API or log access can return authorization errors | secret scope and host clock |

Because `force_pull=False`, an existing local `ons-etl:local` is used. Rebuild
it after changing `DDL/`, `ETL/`, the root requirements, or the root
`Dockerfile`:

```bash
docker compose --profile manual build seed-oltp
```

## Manual Compose flow

The former Compose-only path remains available only through the `manual`
profile:

```bash
docker compose --profile manual up --build \
  seed-oltp oltp-to-vault vault-to-galaxy
```

Without `--profile manual`, those three services do not start and cannot race
the normal Airflow run. Use the manual profile only while the DAG is paused and
has no active run; deliberately starting both paths can still make them write
to the same project database at the same time.

## Stopping and resetting

Keep databases, logs, and the generated login:

```bash
docker compose down
```

Remove every named volume and start from zero:

```bash
docker compose down --volumes
```

The second command permanently removes project data, Airflow metadata, task
logs, ETL logs, and the generated local login. It is a reset command, not a
normal stop command.

## What to memorize

Memorize these ideas:

- Compose owns infrastructure; Airflow owns orchestration; DockerOperator owns
  workload container creation.
- All three tasks use `ons-etl:local` and join `ons-network`.
- Containers reach the project database at `postgres:5432`, never
  `localhost`.
- OLTP and ETL users are separate; Airflow metadata credentials never enter a
  workload.
- A failed stage blocks the stages after it.
- The Docker socket is powerful and this direct mount is local-only.
- Do not run the manual profile beside an active DAG run.

Consult this guide for:

- secret-generation commands;
- exact build, migration, trigger, and reset commands;
- socket group troubleshooting;
- retry and timeout numbers;
- log and failed-container inspection commands.

The goal is to understand the boundaries and failure behavior, not memorize
every flag.

## Validation status of this revision

The Python DAG and test modules compile, the Compose YAML parses, all 27
repository tests pass, and Git's whitespace check is clean.

Docker is not installed in the environment where this revision was prepared:
the `docker` command is not available. Therefore the following checks have not
been executed here:

- `docker compose config --quiet`;
- both image builds;
- `airflow-init`;
- service health checks;
- `airflow dags list-import-errors` inside the running stack;
- a manual DAG trigger and the complete OLTP -> Data Vault -> Galaxy run.

This revision has static validation, not an end-to-end Docker validation. Run
the commands in this guide on a Docker-enabled host before treating the local
stack as E2E-verified.

## Review order

For an educational file-by-file review:

1. `.env.example` — identities, secrets, and local defaults;
2. root `Dockerfile` — the reusable workload image;
3. `Dockerfile.airflow` and `airflow/requirements.txt` — orchestration image;
4. `airflow/dags/ons_enterprise_pipeline.py` — task contract and lineage;
5. `compose.yaml` — infrastructure, secret scope, socket, and network;
6. `tests/test_airflow_orchestration.py` — architectural regression checks.

Official references:

- [DockerOperator reference](https://airflow.apache.org/docs/apache-airflow-providers-docker/stable/_api/airflow/providers/docker/operators/docker/index.html)
- [Airflow Connections from environment variables](https://airflow.apache.org/docs/apache-airflow/stable/howto/connection.html)
- [Airflow 3.3.1 configuration reference](https://airflow.apache.org/docs/apache-airflow/3.3.1/configurations-ref.html)
- [Airflow security model](https://airflow.apache.org/docs/apache-airflow/stable/security/security_model.html)
