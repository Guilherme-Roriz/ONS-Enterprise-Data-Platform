# Docker Development Guide

- **Project:** ONS Enterprise Data Platform
- **Scope:** ETL containerization
- **Status:** Configuration complete; runtime validation pending

---

## 1. Goal

The current Docker design packages both ETL stages into one reusable Python
image and runs them as two separate, sequential containers:

```text
Dockerfile
    |
    v
ons-etl image
    |-- oltp-to-vault container
    `-- vault-to-galaxy container
```

The containers share the same code and dependencies, but Docker Compose gives
each container a different Python command.

## 2. Image, Container, Build, and Run

- A **Dockerfile** is the recipe used to create an image.
- An **image** is an immutable package containing Python, dependencies, and ETL
  code.
- A **container** is a running or stopped instance of an image.
- `docker compose build` downloads the base image, installs dependencies, and
  creates the ETL image.
- `docker compose up` creates and runs the containers from that image.

The Dockerfile does not download or execute anything by itself. Docker only
follows its instructions when a build command is executed.

## 3. Current Files

| File | Responsibility |
|---|---|
| `Dockerfile` | Builds the shared ETL image. |
| `.dockerignore` | Removes secrets, caches, logs, tests, and development files from the build context. |
| `compose.yaml` | Defines the two ETL jobs, their execution order, network, environment, and log volume. |
| `.env.example` | Documents the required configuration without exposing real credentials. |

These files remain at the repository root because the Docker build context is
the project root and needs direct access to `requirements.txt` and `ETL/`.

## 4. Image Design

The shared image uses `python:3.13-slim`, installs `requirements.txt`, and copies
the complete `ETL/` package, including its YAML mappings and SQL transformations.

Dependencies are copied and installed before the ETL source code. This allows
Docker to reuse the dependency layer when application code changes without a
change to `requirements.txt`.

The image runs as the non-root Linux user `etl`. This user is unrelated to the
PostgreSQL role configured through `DB_USER`.

## 5. Compose Design

`x-etl-common` is a reusable YAML configuration block, not a third container.
Both services inherit it and use the same `ons-etl:local` image.

The services run these commands:

```text
oltp-to-vault:   python -m ETL.data_vault.main
vault-to-galaxy: python -m ETL.galaxy.main
```

`vault-to-galaxy` uses `service_completed_successfully`, so it starts only after
`oltp-to-vault` exits with status code `0`. A failed first stage therefore blocks
the dependent transformation.

The services are one-time jobs rather than long-running servers, so their
restart policy is `"no"`.

## 6. Network and Logs

Both ETL services join the `ons-network` bridge network. The network currently
provides an isolated project boundary and will later allow the ETLs to reach a
containerized PostgreSQL service by its service name.

The `etl-logs` named volume is mounted at `/app/ETL/logs`. It preserves ETL log
files independently of the lifecycle of an individual container.

## 7. Environment Configuration

Real credentials must never be committed. Each developer creates a local `.env`
from the versioned template:

```bash
cp .env.example .env
```

PowerShell equivalent:

```powershell
Copy-Item .env.example .env
```

The developer must then replace the placeholder values in `.env`.

- `DB_HOST=localhost` is used when Python runs directly on the host.
- `DOCKER_DB_HOST=host.docker.internal` allows an ETL container to reach a
  PostgreSQL instance running on the host machine.
- When PostgreSQL becomes a Compose service, `DOCKER_DB_HOST` will use the
  database service name instead.

`DB_USER` should identify a dedicated, non-superuser PostgreSQL role. The role
name is configurable, but the role must exist and have the permissions required
to read `oltp` and load `data_vault`, `galaxy`, and `etl`.

## 8. Commands for Future Runtime Validation

Run these commands from the repository root after Docker is installed and `.env`
has been configured:

```bash
docker compose config --quiet
docker compose build
docker compose up
```

Useful inspection commands:

```bash
docker compose ps --all
docker compose logs oltp-to-vault
docker compose logs vault-to-galaxy
```

Remove the project containers and network while preserving the named log volume:

```bash
docker compose down
```

## 9. Planned PostgreSQL Container

Database containerization is intentionally deferred, but it is part of the
planned architecture:

```text
ons-network
|-- postgres
|-- oltp-to-vault
`-- vault-to-galaxy
```

The PostgreSQL implementation should add:

1. An official PostgreSQL image.
2. A named volume for durable database storage.
3. A health check using `pg_isready`.
4. ETL dependencies on a healthy database.
5. Initialization scripts for the existing DDL files.
6. A dedicated non-superuser ETL role and explicit grants.
7. The PostgreSQL service name as `DOCKER_DB_HOST`.

This is the point at which a dedicated `docker/postgres/` directory may become
useful for initialization and permission scripts. No real passwords should be
stored in those scripts.

## 10. Validation Checklist

- [x] Dockerfile created.
- [x] Docker build context exclusions defined.
- [x] Two sequential ETL services defined.
- [x] Shared network and persistent log volume defined.
- [x] Environment template documented.
- [x] Compose YAML structure parsed successfully.
- [ ] Docker image built locally.
- [ ] OLTP to Data Vault container completed successfully.
- [ ] Data Vault to Galaxy container completed successfully.
- [ ] Log persistence verified.
- [ ] PostgreSQL service containerized.
