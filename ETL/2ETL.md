# Data Vault → Galaxy ETL

## Overview

This is the second ETL stage of the ONS Enterprise Data Platform. It transforms the integrated `data_vault` layer into the `galaxy` fact constellation used for analytics.

The pipeline is configuration-driven. YAML files define the execution order, source, target, and SQL transformation; the Python engine discovers and executes them. PostgreSQL performs the set-based transformations so joins, effective-date resolution, and upserts remain atomic and efficient.

## Load order

1. Seed `dim_date` and the 1,440-row `dim_time_of_day`.
2. Upsert the Type 1 reference dimensions: state, occurrence type, and maintenance type.
3. Build Type 2 power-plant, substation, and transmission-line dimensions from the union of attribute and status satellite timelines.
4. Upsert generation, transmission, monitoring, occurrence, maintenance, and asset-status facts.

Dimension surrogate keys are resolved with the version valid at each reading, event, work-order, or snapshot date. State is inherited from the asset; transmission-line state is derived from its origin substation.

## Idempotency and history

- Reference dimensions use their Data Vault hash key as the upsert key.
- Type 2 dimensions use `(hash_key, start_date)` and recalculate `end_date` from the next Vault change boundary.
- Facts use the grain constraints defined in `DDL/fact_constelation.sql`.
- Rerunning a load updates corrected measures and attributes without duplicating rows.
- Each mapping runs in its own database transaction. A failure rolls back that mapping, writes a `FAILED` audit row, and stops downstream loads.

The engine writes execution metadata to `etl.etl_control`, including source, target, status, affected-row count, timing, and an error message when applicable.

## Directory structure

```text
ETL/galaxy/
├── core/engine.py       # Discovery, transactions, execution, and auditing
├── mappings/*.yaml      # Ordered pipeline metadata
├── sql/*.sql            # Set-based PostgreSQL transformations
└── main.py              # CLI entry point
```

## Prerequisites

1. Python 3.11 or newer.
2. Install dependencies with `pip install -r requirements.txt`.
3. Create the database structures in this order:

   ```bash
   psql -f DDL/oltp.sql
   psql -f DDL/datavault.sql
   psql -f DDL/fact_constelation.sql
   psql -f DDL/etl.sql
   ```

4. Copy `.env.example` to `.env` and set the PostgreSQL credentials.
5. Complete the OLTP → Data Vault ETL before running this stage.

The engine also creates or upgrades `etl.etl_control` automatically. The explicit DDL remains useful for controlled deployments.

If the Galaxy v1.7 DDL was already applied, upgrade it in place before the first load:

```bash
psql -f DDL/migrations/001_galaxy_etl_prerequisites.sql
```

The migration is non-destructive. It adds the dimension upsert indexes and widens percentage fields so `100.0000` is valid.

## Running

From the repository root:

```bash
python -m ETL.galaxy.main
```

The default calendar horizon is 2000-01-01 through 2050-12-31. Vault dates outside that range are included automatically. Override the configured horizon when needed:

```bash
python -m ETL.galaxy.main --start-date 2010-01-01 --end-date 2060-12-31
```

## Derived fields and known source limits

- `capacity_factor_pct` is generation output divided by the installed capacity valid at the reading date, multiplied by 100.
- `asset_age_years` is populated for plants because the Vault contains plant commissioning dates. It remains null for substations and lines because no commissioning date exists for those entities.
- `line_loading_pct` remains null because neither the OLTP nor Data Vault model contains a thermal-limit/rated-capacity attribute. Populating it from voltage would be technically incorrect. Once a line rating is added to the source and `sat_line_attributes`, the transformation can calculate this measure directly.
- `holiday_flag` defaults to false and is deliberately not overwritten on reruns, allowing a future holiday reference load to maintain it.

## Adding a transformation

Add one SQL file under `ETL/galaxy/sql` and one YAML mapping under `ETL/galaxy/mappings`. Each mapping requires:

```yaml
pipeline: descriptive_unique_name
order: 160
source: data_vault.source_table
target: galaxy.target_table
sql_file: transformation.sql
```

Order values and pipeline names must be unique. Target identifiers and SQL paths are validated before any database work begins.
