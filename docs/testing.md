# Testing and Data Quality

The test strategy protects business behavior across the complete data path. It
does not use coverage percentage as a substitute for meaningful contracts.
Pure logic is checked quickly in isolation; PostgreSQL behavior is checked
against PostgreSQL 17; and the final E2E scenario runs every application entry
point twice to prove consistency after a rerun.

## Progress checklist

- [x] Inspect current branch
- [x] Locate existing tests
- [x] Sync `feature/testing` with `main`
- [x] Map critical contracts
- [x] Configure pytest / markers / fixtures
- [x] Isolated PostgreSQL test environment
- [x] Unit tests
- [x] Integration tests
- [x] Seed / idempotency tests
- [x] Data Vault Data Quality
- [x] Galaxy Data Quality
- [x] Failure paths / rollback
- [x] Cross-layer validation
- [x] E2E
- [ ] Airflow scheduler / DockerOperator E2E
- [x] Final documentation

## Verified status

GitHub Actions run
[#5](https://github.com/Guilherme-Roriz/ONS-Enterprise-Data-Platform/actions/runs/34850604366)
completed successfully on 2026-09-14:

- 36 unit tests passed on Python 3.12;
- 13 PostgreSQL tests passed against an isolated PostgreSQL 17 container;
- those 13 tests comprise 11 integration tests, one Data Quality contract, and
  one E2E rerun scenario;
- the PostgreSQL job completed in 1 minute 53 seconds and destroyed its test
  database afterwards.

The successful E2E path was:

```text
empty post-bootstrap database
-> deterministic OLTP seed
-> OLTP to Data Vault
-> Data Vault to Galaxy
-> cross-layer quality assertions
-> complete rerun
-> identical row counts and business totals
```

## Suite structure

```text
tests/
├── conftest.py
├── unit/
├── integration/
├── data_quality/
└── e2e/
```

`pytest.ini` registers strict markers and limits discovery to `tests/`.
`requirements-test.txt` extends the application requirements with pytest.

### Markers

| Marker | Purpose | PostgreSQL required |
| --- | --- | --- |
| `unit` | Pure functions, parsing, mappings, entry points, seed and Airflow contracts | No |
| `integration` | Real constraints, roles, transactions, seed, ETL and SCD2 behavior | Yes |
| `data_quality` | Data Vault, Galaxy and cross-layer assertions | Yes |
| `e2e` | Empty environment through complete pipeline and rerun | Yes |
| `failure_path` | Expected connection, schema, table and transaction failures | Yes |

Database-dependent tests are skipped unless `--run-integration` or `--run-e2e`
is explicitly supplied. This prevents an accidental connection to a developer
database during an ordinary local run.

## Fixtures and isolation

`compose.test.yaml` creates a dedicated `ons_edp_test` database on host port
`55432`. It uses separate test-only admin, OLTP and ETL roles, a dedicated
network, the same DDL/bootstrap scripts as the application, and a `tmpfs`
PostgreSQL data directory. It does not mount or reuse the development volume.

The main fixtures in `tests/conftest.py` provide:

- a session guard that verifies the database name and PostgreSQL 17 server;
- admin and least-privilege ETL connections;
- a reset that truncates mutable OLTP, Vault, Galaxy and audit tables while
  preserving the 27-row junk dimension created by bootstrap;
- subprocess runners with test-only environment variables for each real entry
  point;
- a fully loaded pipeline fixture for cross-layer assertions.

All integration and E2E tests use PostgreSQL. SQLite is not part of the suite.

## Commands

Install dependencies and run the fast suite:

```bash
python -m pip install -r requirements-test.txt
python -m pytest -m unit -q
```

Run integration and Data Quality locally on a Docker-capable machine:

```bash
docker compose -f compose.test.yaml up -d --wait test-db
python -m pytest -m "integration or data_quality" --run-integration -q
docker compose -f compose.test.yaml down --volumes
```

Run the complete E2E scenario:

```bash
docker compose -f compose.test.yaml up -d --wait test-db
python -m pytest -m e2e --run-e2e -q
docker compose -f compose.test.yaml down --volumes
```

The workflow `.github/workflows/testing.yml` runs unit tests first, then starts
the isolated database and runs Integration, Data Quality and E2E. It is
triggered by pushes to `feature/testing`, pull requests targeting `main`, and
manual dispatches.

## Airflow scheduler and DockerOperator E2E

The orchestration E2E is now prepared as a separate `airflow` job in the same
workflow. It intentionally uses the production `compose.yaml` with an
isolated Compose project (`ons-airflow-e2e`), database name
`ons_edp_airflow_test`, host port `55433`, test-only credentials and fresh
volumes. The development stack is not reused.

The job performs this sequence:

```text
build ETL and Airflow images
→ start postgres, airflow-db, airflow-init, API server, scheduler and DAG processor
→ confirm the application database is empty
→ wait for DAG discovery and assert zero import errors
→ unpause and trigger ons_enterprise_data_pipeline through the Airflow CLI
→ poll Airflow metadata until the scheduler reports success
→ assert seed_oltp, load_data_vault and publish_galaxy are all successful
→ run Data Quality assertions and save a pipeline snapshot
→ trigger a second DAG run
→ repeat Data Quality assertions and compare the snapshot for idempotency
→ collect diagnostics and remove all Compose volumes
```

The driver is `tests/e2e/run_airflow_dag.sh`; the result contract is
`tests/e2e/test_airflow_orchestration_result.py`; and the `orchestration`
marker plus `--run-orchestration` flag keep this slower test separate from the
direct-entrypoint E2E. The test also validates empty state, Airflow import
errors, `dag_run` state, all three `task_instance` states, row counts, audit
successes, cross-layer totals and equality between the first and second run.

This job has been implemented but **has not yet been executed**. The next
session must push the pending branch changes, monitor the new GitHub Actions
job, and fix any Airflow 3.3.1/runner-specific issue revealed by the real
Docker run before checking this item off. Do not describe the orchestration
E2E as passed until that workflow job finishes successfully.

## Critical contracts

### Seed and OLTP

- business-key lookup returns the database's real surrogate IDs;
- first run produces the expected deterministic data set;
- second run produces no duplicate rows or changed business values;
- a partially populated database is reconciled without assuming identity IDs;
- generators and SCD2 effective timestamps are deterministic;
- the seed contains no `TRUNCATE`, `DELETE` or `DROP` reset;
- CHECK constraints, foreign keys and the available-capacity trigger reject
  invalid data;
- OLTP and ETL roles cannot write outside their responsibility boundaries.

### Data Vault

- all hub business keys match the OLTP source sets;
- hub hashes equal PostgreSQL SHA-256 hashes of the business keys;
- hub, link and satellite foreign keys remain valid;
- each SCD2 parent has exactly one current row and no overlapping versions;
- a changed plant closes its prior Vault version and opens one new version;
- transactional satellites retain the source grain and totals.

### Galaxy

- conformed and SCD2 dimensions have the expected source cardinality;
- the calendar is contiguous and covers the operational date range;
- each fact table preserves its declared grain;
- asset facts select exactly one asset dimension;
- fact counts and generation totals reconcile with OLTP and Data Vault;
- a changed plant is represented by non-overlapping Galaxy SCD2 versions.

## Failure paths

The suite verifies unavailable database and invalid-password processes return a
non-zero exit code. It also verifies missing schema/table errors are recorded as
failed audit events, CHECK/FK/trigger violations reject invalid data, a forced
mid-transaction failure rolls back its target write, the failed attempt remains
auditable, and a corrected rerun succeeds cleanly.

## Limitations

- The direct-entrypoint E2E is verified. The new scheduler/DockerOperator E2E
  is implemented in CI but remains pending its first real execution.
- Airflow/DockerOperator topology is protected by unit-level architectural
  contracts; a full Airflow runtime test remains separate operational work.
- The suite does not currently include performance, concurrency, lock-contention
  or large-volume tests.
- Mutation-based SCD2 history is exercised for the power-plant dimension. The
  other SCD2 satellites are checked for current-row uniqueness and interval
  overlap on the complete load.
- The corporate development notebook cannot run Docker because hardware
  virtualization is unavailable. Real-database verification therefore runs on
  the GitHub-hosted Linux runner.
