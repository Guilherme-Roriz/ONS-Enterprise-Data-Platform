# OLTP → Data Vault ETL

## Overview

This is the first ETL stage of the ONS Enterprise Data Platform. It loads the operational `oltp` schema into the integrated `data_vault` schema defined by `DDL/datavault.sql`.

The implementation uses the same architecture as the Galaxy ETL: ordered YAML mappings are discovered by a generic Python engine, while PostgreSQL performs the set-based transformations. This keeps orchestration separate from entity-specific joins, hashing, SCD handling, and upsert logic.

## Coverage

Thirteen source-domain steps populate the complete Raw Vault:

| Order | Source | Targets |
|---:|---|---|
| 10 | `oltp.state` | State hub and SCD1 satellite |
| 20 | `oltp.occurrence_type` | Occurrence-type hub and SCD1 satellite |
| 30 | `oltp.maintenance_type` | Maintenance-type hub and SCD1 satellite |
| 40 | `oltp.plant` | Plant hub, attribute/status satellites, state link |
| 50 | `oltp.substation` | Substation hub, attribute/status satellites, state link |
| 60 | `oltp.transmission_line` | Line hub, attribute/status satellites, origin/destination links |
| 70 | `oltp.generation_reading` | Generation-reading satellite |
| 80 | `oltp.measurement` | Substation and line measurement satellites |
| 90 | `oltp.occurrence` | Occurrence hub and detail satellite |
| 100 | `oltp.occurrence_asset` | Three occurrence-to-asset links |
| 110 | `oltp.work_order` | Work-order hub and detail satellite |
| 120 | `oltp.work_order_asset` | Three work-order-to-asset links |
| 130 | `oltp.asset_status` | Three daily snapshot satellites |

Together these steps cover all 8 hubs, 9 links, and 17 satellites in the Data Vault DDL.

## Directory structure

```text
ETL/
├── common/
│   └── control.py             # Audit table shared by both ETL stages
├── config/
│   └── database.py            # Shared PostgreSQL configuration
├── data_vault/
│   ├── core/
│   │   └── engine.py          # Mapping discovery, transactions, and auditing
│   ├── mappings/*.yaml        # Ordered source/target metadata
│   ├── sql/*.sql              # Set-based Vault transformations
│   └── main.py                # First-stage CLI
└── utils/
    ├── hash.py
    └── logger.py
```

## Hashing rules

- Hub hash keys are SHA-256 hexadecimal hashes of the source business key.
- Link hash keys are SHA-256 hashes of the participating hub hashes concatenated in DDL order.
- The transmission-line/substation link also includes `ORIGIN` or `DESTINATION` in its hash input.
- Hashdiffs use a pipe-delimited canonical representation of descriptive attributes, with `∅` representing null.
- `record_source` is `ONS_OLTP`.

PostgreSQL's built-in `sha256(bytea)` and `encode(..., 'hex')` functions produce the same 64-character representation used by the Python hash utility.

## Load behavior

### Hubs and links

Hubs and links are insert-only. Existing hash keys use `ON CONFLICT DO NOTHING`, making reruns idempotent.

### SCD1 reference satellites

State, occurrence type, and maintenance type are scanned in full because their OLTP tables have no update timestamp. They use `ON CONFLICT DO UPDATE`, but update only when the hashdiff changes.

### SCD2 satellites

Plant, substation, line, occurrence, and work-order history uses the source `last_updated` date as the effective `start_date`:

1. An unchanged hashdiff is skipped.
2. A changed current version is closed with an exclusive `end_date`.
3. A new current version is inserted.
4. Multiple changes on the same calendar day update that day's version because the Vault DDL uses `DATE`, not `TIMESTAMP`, in its SCD2 primary key.

Partial unique indexes enforce at most one open version per parent hash key.

### Transactional and snapshot satellites

Generation readings and electrical measurements upsert on `(asset_hash, reading_timestamp)`. Daily asset snapshots upsert on `(asset_hash, snapshot_date)`. Corrected source measurements therefore propagate without creating duplicate grain rows.

## Transactions and auditing

Each mapping runs in its own database transaction. A failed transformation is rolled back, logged to `etl.etl_control`, and stops later dependent steps. Successful audit rows contain the source, all target tables, affected-row count, timestamps, and duration.

The engine validates mapping fields, SQL paths, source identifiers, target identifiers, unique pipeline names, and unique execution-order values before opening a database connection.

## Configuration

Copy `.env.example` to `.env` and configure either `DATABASE_URL` or the individual settings:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=ons_edp
DB_USER=etl_user
DB_PASSWORD=change_me
```

Install dependencies:

```bash
pip install -r requirements.txt
```

## Database preparation

For a new database, apply:

```bash
psql -f DDL/oltp.sql
psql -f DDL/datavault.sql
psql -f DDL/etl.sql
```

For an existing Data Vault v1.2 database, apply the non-destructive integrity-index migration:

```bash
psql -f DDL/migrations/002_data_vault_etl_prerequisites.sql
```

If the migration reports duplicate open satellite rows, reconcile those rows before retrying; the constraint is deliberately protecting the one-current-version invariant.

## Running

From the repository root:

```bash
python -m ETL.data_vault.main
```

After it succeeds, run the dimensional stage:

```bash
python -m ETL.galaxy.main
```

Both commands return a nonzero exit status after a failed step, which makes them suitable for schedulers and CI jobs.

## Adding a source domain

Add one SQL file under `ETL/data_vault/sql` and one YAML mapping under `ETL/data_vault/mappings`:

```yaml
pipeline: example
order: 140
source: oltp.example
targets:
  - data_vault.hub_example
  - data_vault.sat_example_attributes
sql_file: example.sql
```

Every SQL transformation must return one row containing an integer `rows_processed` value so the engine can audit affected rows without scanning target tables.
