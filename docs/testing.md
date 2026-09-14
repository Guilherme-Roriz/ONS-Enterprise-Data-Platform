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
- [x] Airflow scheduler / DockerOperator E2E
- [x] Final documentation

## Verified status

The complete workflow passed in GitHub Actions run
[#9](https://github.com/Guilherme-Roriz/ONS-Enterprise-Data-Platform/actions/runs/34882377677)
on 2026-09-14, testing commit `90c073e`:

- 37 unit tests passed;
- 13 direct PostgreSQL tests passed (the orchestration test is deliberately
  skipped in that job);
- the Airflow job built both images and started the complete stack;
- the empty-state check passed, then both the automatic daily run and manual
  rerun passed their task-state, execution-order and Data Quality assertions;
- all six task instances were `DockerOperator`, `success`, attempt 1;
- the first and second snapshots matched, with 27 and 54 successful ETL audit
  steps respectively;
- the environment teardown completed successfully.

The orchestration job reported `1 passed` for the empty database, `2 passed`
after the daily run and `2 passed` after the manual rerun. These are repeated
checks of two test functions, not five distinct test cases. The validated run
IDs were `scheduled__2026-09-14T09:00:00+00:00` and
`ci_34882377677_1_second`.

### Earlier direct-entrypoint baseline

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
| `orchestration` | Real scheduler, DockerOperator task states and resulting data | Yes, plus Airflow and Docker |
| `failure_path` | Expected connection, schema, table and transaction failures | Yes |

Database-dependent tests are skipped unless `--run-integration`, `--run-e2e`
or `--run-orchestration`
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

The orchestration E2E runs as a separate `airflow` job in the same
workflow. It intentionally uses the production `compose.yaml` with an
isolated Compose project (`ons-airflow-e2e`), database name
`ons_edp_airflow_test`, host port `55433`, test-only credentials and fresh
volumes. The GitHub job runs on a fresh hosted Linux runner. The production
network name `ons-network` and image tags are retained, so this job must use
a dedicated Docker host; a different Compose project name alone does not
isolate the hard-coded network and images from a running development stack.

The job performs this sequence:

```text
build ETL and Airflow images
→ start postgres, airflow-db, airflow-init, API server, scheduler and DAG processor
→ confirm the application database is empty
→ wait for DAG discovery and assert zero import errors
→ unpause ons_enterprise_data_pipeline and wait for its automatic daily run
→ poll Airflow metadata until the scheduler reports success
→ assert all three tasks are successful DockerOperators, in dependency order
→ run Data Quality assertions and save a pipeline snapshot
→ trigger a second DAG run manually through the Airflow CLI
→ repeat Data Quality assertions and compare the snapshot for idempotency
→ collect diagnostics and remove all Compose volumes
```

The driver is `tests/e2e/run_airflow_dag.sh`; the result contract is
`tests/e2e/test_airflow_orchestration_result.py`; and the `orchestration`
marker plus `--run-orchestration` flag keep this slower test separate from the
direct-entrypoint E2E. The test also validates empty state, Airflow import
errors, `dag_run` state, all three `task_instance` states, row counts, audit
successes, cross-layer totals and equality between the first and second run.
The Data Quality fixture does not reset or reload the database in orchestration
mode: it inspects only data produced by Airflow. The audit contract expects
27 successful ETL steps after the daily run and 54 after the manual rerun.
Snapshot equality covers all mutable application-table row counts and selected
business totals, not byte-for-byte equality of every row.

The first real execution exposed two test-harness issues: the workflow used
the unavailable `runner` context at job-level environment scope, and unpausing
the DAG created its due daily run before the script's manual trigger. The
snapshot path is now configured inside a step; the test explicitly validates
the automatic run before submitting the manual rerun. It keeps the production
DAG, cron expression and Docker commands intact.

This job was executed successfully in run #9 linked above. To repeat it, push
to `feature/testing`, or use **Actions → Testing and Data Quality → Run
workflow** and select that branch when manual dispatch is available. The
workflow contains the full test-only environment and ordered commands. An
ordinary local `pytest` invocation never starts Airflow; passing
`--run-orchestration` only enables assertions against an already loaded
orchestration test database.

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

- The Airflow E2E validates the due daily run after unpausing and a manual
  rerun on one Linux runner. It does not wait for a future 06:00 clock boundary
  or validate scheduler recovery after a restart.
- ETL fault injection, rollback and corrected rerun are validated directly
  as listed in Failure paths above. Forced
  DockerOperator failure, Airflow retry exhaustion and recovery are not part
  of this orchestration scenario; the successful task instances used attempt 1.
- The suite does not currently include performance, concurrency, lock-contention
  or large-volume tests.
- Mutation-based SCD2 history is exercised for the power-plant dimension. The
  other SCD2 satellites are checked for current-row uniqueness and interval
  overlap on the complete load.
- The corporate development notebook cannot run Docker because hardware
  virtualization is unavailable. Real-database verification therefore runs on
  the GitHub-hosted Linux runner.
