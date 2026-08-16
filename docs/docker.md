# Running the project with Docker

![Docker network architecture](assets/docker-network.png)

The Docker setup runs the same flow used by the project: start PostgreSQL, load
the synthetic OLTP data, move it into Data Vault, and finally build the Galaxy
model.

```text
postgres -> seed-oltp -> oltp-to-vault -> vault-to-galaxy
```

I kept the stack intentionally small. It contains only what the pipeline needs
today.

## What Compose starts

- `postgres` runs PostgreSQL 17 and stays available after the pipeline finishes.
- `seed-oltp` runs `DDL/populate.py` and creates the sample operational data.
- `oltp-to-vault` runs the first ETL.
- `vault-to-galaxy` runs the dimensional ETL.

The three Python jobs share the same `ons-etl:local` image. Their dependencies
are identical; only the command and database user change.

Compose waits for PostgreSQL to become healthy before loading data. After that,
each job starts only if the previous one exits successfully. Seeing the three
Python containers as `Exited (0)` is therefore the expected result, not an
error.

## Before the first run

Create your local environment file:

```powershell
Copy-Item .env.example .env
```

Using Bash:

```bash
cp .env.example .env
```

Open `.env` and replace the example passwords. This file stays local and should
never be committed.

The database uses three separate accounts on purpose:

- `POSTGRES_ADMIN_USER` initializes PostgreSQL.
- `OLTP_USER` can load the operational tables.
- `DB_USER` is used by both ETLs.

The last two are non-superuser roles. The administrator password is not passed
to the Python containers.

`DOCKER_DB_HOST` should remain `postgres`, which is the database service name
inside the Compose network. `DB_HOST` and `DB_PORT` are still useful when
running Python directly from the host.

## What happens to the database

The first time PostgreSQL starts with an empty `postgres-data` volume, it runs
`docker/postgres/init/10-bootstrap.sh`. That script creates the application
roles, applies the DDL, and grants the permissions needed by each job.

The DDL order is:

1. `DDL/oltp.sql`
2. `DDL/datavault.sql`
3. `DDL/fact_constelation.sql`
4. `DDL/etl.sql`

This bootstrap runs only for an empty database volume. If a DDL or permission
change does not appear after restarting the containers, the existing volume is
usually the reason.

## Running the pipeline

From the repository root:

```bash
docker compose config --quiet
docker compose up --build -d
docker compose logs -f seed-oltp oltp-to-vault vault-to-galaxy
```

`Ctrl+C` stops following the logs; it does not stop the containers.

Check the final state with:

```bash
docker compose ps --all
```

The successful result is a healthy `postgres` service and exit code `0` for the
other three containers.

## Useful commands

Run the jobs again against the existing database:

```bash
docker compose up -d seed-oltp oltp-to-vault vault-to-galaxy
```

The data generator notices when the OLTP fixture already exists and skips it.
The ETLs can also be run again without duplicating their results.

Stop the stack without deleting the database or logs:

```bash
docker compose down
```

Start from a completely empty database:

```bash
docker compose down --volumes
```

Be careful with the last command. It permanently removes the local PostgreSQL
data and the persisted ETL logs.

## Connecting from the host

Use `localhost`, the value of `POSTGRES_PORT`, and the database name configured
in `DB_NAME`. Containers inside the network use `postgres:5432` instead.

If the host port is already taken, change `POSTGRES_PORT` in `.env`. There is no
need to change the internal port.

## Files involved

- `Dockerfile` builds the Python image used by the three jobs.
- `compose.yaml` connects the services and controls their order.
- `.env.example` lists the local configuration without real secrets.
- `.dockerignore` keeps secrets, caches, tests, and local files out of the image.
- `docker/postgres/init/10-bootstrap.sh` prepares PostgreSQL on its first start.
- `DDL/` contains both the schemas and the synthetic data generator.

The configuration has been checked without Docker, and the Python tests pass.
The image build and the first end-to-end run still need to be done on a machine
with Docker installed.
