# ONS Enterprise Data Platform

## OLTP → Data Vault Ingestion Framework

### 1. Overview

The **ONS Enterprise Data Platform – OLTP to Data Vault ingestion framework** is a generic, configuration-driven Python pipeline that moves data from the transactional layer (OLTP) into the historical, normalized Data Vault 2.0 model.

The framework contains **no entity‑specific logic**. Every source table, target table, business key, descriptive column, and relationship is defined in external YAML mapping files. Adding a new entity to the pipeline requires only a new YAML file—no Python code changes.

---

### 2. Architecture

```
┌────────────────────┐
│   YAML Mappings    │  (one per entity)
│   /mappings/*.yaml │
└────────┬───────────┘
         │ auto‑discovery
         ▼
┌─────────────────────┐
│ Engine (engine.py)  │  Generic orchestrator
└────────┬────────────┘
         │ uses
         ▼
┌─────────────────────┐
│ Specialized Loaders │  Hub, Satellite, Link
└────────┬────────────┘
         │ writes to
         ▼
┌─────────────────────┐
│    PostgreSQL       │
│  OLTP  ──►  Vault   │
└─────────────────────┘
```

Key design principles:

- **Total decoupling** – The engine never knows what a “Plant” or a “Generation” is.
- **Idempotency** – Pipelines can be re‑run safely; Hubs use `ON CONFLICT DO NOTHING`, Satellites compare hashdiffs.
- **Incremental loading** – After an initial full load, only new or changed records are processed, driven by the `etl.etl_control` table.
- **Hash‑centric** – All primary and foreign keys in the Vault are SHA‑256 hashes, eliminating dependency on source system identifiers.

---

### 3. Directory Structure

```
etl/
├── config/
│   └── database.py          # Database connection via .env
├── core/
│   ├── engine.py             # Generic ingestion engine
│   ├── hub_loader.py         # Hub loading logic
│   ├── satellite_loader.py   # Satellite loading logic
│   ├── link_loader.py        # Link loading logic
│   └── control.py            # ETL control table management
├── mappings/                 # One YAML file per entity
│   ├── plants.yaml
│   ├── generation.yaml
│   ├── substations.yaml
│   └── ...
├── utils/
│   ├── logger.py             # Centralized logging configuration
│   └── hash.py               # SHA‑256 hash generation
├── logs/
│   └── etl.log               # Application log file
└── main.py                   # Entry point
```

---

### 4. Environment Configuration (.env)

Create a `.env` file in the project root with your PostgreSQL credentials:

```
DB_HOST= ------
DB_PORT= -----
DB_NAME= -----
DB_USER= ----
DB_PASSWORD= ------
LOG_LEVEL= ----
```

These values are read by `python-dotenv` in `database.py`. No credentials are stored in the source code.

---

### 5. Mapping Files (YAML)

Each entity to be loaded has a dedicated YAML file inside `etl/mappings/`. The filename (without extension) becomes the pipeline name used in logs and the control table.

#### 5.1 Basic Structure

```yaml
source_table: oltp.plants               # OLTP source table
hub_table: vault.hub_plant              # Target Hub table
satellite_table: vault.sat_plant        # Main Satellite table
business_key: plant_id                  # Natural business key column
incremental_column: id                  # Column for incremental high‑water mark
load_date_column: load_datetime         # Load date/time column
hash_columns:                           # Descriptive columns monitored for changes
  - plant_name
  - region
  - installed_capacity
  - status
hub_hash_key_column: hub_plant_id       # Hash key column name in the Hub
hub_business_key_column: plant_id       # Business key column name in the Hub
satellite_hashdiff_column: hash_diff    # Hashdiff column name in the Satellite
satellite_hub_key_column: hub_plant_id  # Foreign key column in the Satellite referencing the Hub
```

#### 5.2 Links (Relationships)

If the entity participates in relationships, add a `links` block:

```yaml
links:
  - link_table: vault.link_plant_substation
    left_source_column: plant_id
    right_source_column: substation_id
    left_hub_hash_key_column: hub_plant_id
    right_hub_hash_key_column: hub_substation_id
    left_link_key_column: hub_plant_id
    right_link_key_column: hub_substation_id
```

Each link processes the natural keys directly from the source table and inserts unique pairs into the Link table.

---

### 6. Framework Components

#### 6.1 `engine.py` – Ingestion Engine

Class `ETLIngestionEngine`:

- Scans the `mappings/` folder for `*.yaml` files automatically.
- For each mapping:
  1. Retrieves the last processed ID from `etl.etl_control`.
  2. Reads source data incrementally using `pandas.read_sql`.
  3. Invokes the Hub, Satellite, and Link loaders in order.
  4. Updates the control table with the new maximum ID and statistics.
  5. On failure, records a `FAILED` status and rolls back the entire transaction.
- All operations within a mapping are wrapped in a single database transaction (`engine.begin()`).

#### 6.2 `hub_loader.py`

Responsible for populating the Hub with new business keys.

Logic:

- Extracts distinct values of the business key column.
- Generates the SHA‑256 hash key.
- Inserts with `INSERT … ON CONFLICT DO NOTHING`.

#### 6.3 `satellite_loader.py`

Loads historical versions into the Satellite, detecting changes via a hashdiff.

Logic:

- Computes a SHA‑256 hash of the descriptive columns (`hash_columns`) for each row.
- Fetches the latest hashdiff for every hub key from the Satellite (using `DISTINCT ON`).
- Inserts a new row **only** if no previous version exists or the hashdiff differs.
- Unchanged rows are skipped.

#### 6.4 `link_loader.py`

Populates Link tables from the mapping definitions.

Logic:

- For each link definition, computes left and right hub hash keys from the source columns.
- Deduplicates the pairs.
- Inserts with `ON CONFLICT (left_link_key, right_link_key) DO NOTHING`.

#### 6.5 `control.py`

Manages the `etl.etl_control` table, which stores:

| Column              | Description                                      |
|---------------------|--------------------------------------------------|
| `pipeline`          | Pipeline name (derived from YAML file name)      |
| `source_table`      | Source table                                     |
| `last_processed_id` | High‑water mark ID                               |
| `rows_processed`    | Total rows read from source                      |
| `execution_start`   | Start timestamp                                  |
| `execution_end`     | End timestamp                                    |
| `execution_time`    | Duration in seconds                              |
| `status`            | `SUCCESS` or `FAILED`                            |

Key methods:

- `get_last_processed_id()` – returns the last processed ID, or `0` for an initial load.
- `update_control()` – inserts a new control record after each run.

---

### 7. Utilities

#### 7.1 `hash.py`

Function `generate_hash(value: str) -> str` that returns the SHA‑256 hexadecimal digest. Used to create all hash keys and hashdiffs in the Vault.

#### 7.2 `logger.py`

Configures the root logger with:

- Standardized format: timestamp, level, module, message.
- Dual output: console and `etl/logs/etl.log`.
- Configurable log level via `.env` (default `INFO`).

---

### 8. Typical Execution Flow

1. `main.py` sets up logging and obtains a database engine.
2. `ETLIngestionEngine.run()` iterates over all YAML files.
3. For each pipeline (e.g., `plants`):
   - Executes: `SELECT * FROM oltp.plants WHERE id > 0` (initial load).
   - Hub: inserts new `plant_id` values into `vault.hub_plant`.
   - Satellite: inserts the first version of descriptive columns into `vault.sat_plant`.
   - Link: inserts relationships into `vault.link_plant_substation`.
   - Control: records `last_processed_id = MAX(id)`.
4. On the next execution, the query uses `WHERE id > <previous_max>`, processing only new/changed records.

---

### 9. Error Handling and Transactions

The entire processing of one mapping is wrapped in a database transaction:

```python
with self.engine.begin() as conn:
    # all read and write operations
```

If any exception occurs, the transaction is automatically rolled back, and no partial data is persisted in the Vault. A separate transaction attempts to record the failure in `etl.etl_control`.

All exceptions are logged with a full stack trace.

---

### 10. Logging Example

```
2026-07-30 14:30:01 | INFO     | root   | Starting ONS ETL
2026-07-30 14:30:01 | INFO     | engine | ============================================================
2026-07-30 14:30:01 | INFO     | engine | Starting pipeline 'plants' for source oltp.plants
2026-07-30 14:30:01 | INFO     | engine | Last processed id = 0
2026-07-30 14:30:02 | INFO     | engine | Read 1250 rows from oltp.plants
2026-07-30 14:30:02 | INFO     | hub_loader | Hub vault.hub_plant: 1200 distinct keys found, 50 new keys inserted
2026-07-30 14:30:02 | INFO     | satellite_loader | Satellite vault.sat_plant: 1250 rows processed, 120 inserted, 1130 skipped (no change)
2026-07-30 14:30:02 | INFO     | link_loader | Link vault.link_plant_substation: 100 unique pairs found, 10 inserted
2026-07-30 14:30:02 | INFO     | control | Control record inserted for plants/oltp.plants, status=SUCCESS, rows=1250
2026-07-30 14:30:02 | INFO     | engine | Pipeline 'plants' completed with status SUCCESS (duration 1.0)
```

---

### 11. Running the Framework

```bash
# Install dependencies (use a virtual environment)
pip install pandas sqlalchemy psycopg2-binary python-dotenv pyyaml

# Execute
python -m etl.main
```

Ensure the `.env` file is in the project root and that the OLTP and Vault tables already exist in the database.

---

### 12. Extensibility

To add a new entity (e.g., `ocurrences`):

1. Create `etl/mappings/ocurrences.yaml` following the standard format.
2. Define the Hub, Satellite, and optional Links.
3. Run `python -m etl.main` again. The new pipeline is detected automatically.

**No code changes are required.**

---

### 13. Requirements and Dependencies

- Python ≥ 3.13
- Packages: `pandas`, `SQLAlchemy`, `psycopg2-binary` (or `psycopg`), `python-dotenv`, `PyYAML`
- PostgreSQL database with `oltp`, `vault`, and `etl` schemas already created

---

### 14. Final Remarks

- The framework follows **SOLID** principles and emphasizes reusability, with small, focused functions, type hints, and docstrings throughout.
- The design reflects real‑world data engineering practices, ready for production workloads.
- All business logic resides in the YAML mappings; the Python code is purely infrastructure for moving and versioning data.

This document serves as the complete reference for operating, maintaining, and extending the OLTP → Data Vault ingestion layer of the ONS Enterprise Data Platform.
