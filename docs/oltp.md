# OLTP Source System Documentation
 
**Project:** ONS Enterprise Data Platform  
**Author:** Guilherme Roriz  
**Date:** 23/07/2026  
**Version:** 1.0
 
---
 
## 1. Overview
 
Brief description of the OLTP environment: which operational systems supply data to the analytical platform, their purpose, technology stack, and any relevant constraints.
 
- **System name:** ONS Operational Systems (ERP, SCADA, Maintenance, etc.)
- **DBMS:** PostgreSQL / Oracle / SQL Server
- **Scope:** Power generation, transmission, grid occurrences, maintenance, asset management
- **Connection method:** CDC (change data capture)
 
---
 
## 2. Source Entities and Relationships
 
All tables listed below will be ingested directly into the Data Vault (Enterprise Data Warehouse).  
The Data Lake is reserved exclusively for unstructured and semi-structured data and is not covered here.
 
### 2.1 Generation Domain
| Table Name         | Description                                      | Estimated Volume (rows/day) | Primary Key       | Key Columns                                        |
|--------------------|--------------------------------------------------|-----------------------------|-------------------|----------------------------------------------------|
| plant              | Power plant master data                          | ~100 (static, slowly grows) | plant_id          | plant_id, plant_code                               |
| generation_reading | Minute-level generation measurements per plant   | ~144,000 (100 plants × 1440)| reading_id        | plant_id, reading_timestamp, principal measurements|
 
### 2.2 Transmission & System Monitoring Domain
| Table Name         | Description                                                                 | Estimated Volume (rows/day)            | Primary Key    | Key Columns                     | Principal Measurements (per row)                          |
|--------------------|-----------------------------------------------------------------------------|----------------------------------------|----------------|---------------------------------|-----------------------------------------------------------|
| transmission_line  | Transmission line master data                                               | ~500 (static)                          | line_id        | line_id, line_code              | (master data only)                                        |
| substation         | Substation master data                                                      | ~200 (static)                          | substation_id  | substation_id, substation_code  | (master data only)                                        |
| measurement        | Minute‑level electric measurements at substations and transmission lines    | ~1 440 000 (1000 points × 1440)       | measurement_id | asset_type, asset_id, reading_timestamp | power_flow_mw, losses_mw, frequency_hz, voltage_kv, system_load_mw, reliability_index |
 
**Notes on `measurement`:**
- Each row belongs to exactly one asset, identified by `asset_type` (`'substation'` or `'transmission_line'`) and `asset_id`.
- Not all columns are populated for every asset type – e.g., a substation row will have `frequency_hz`, `voltage_kv`, `system_load_mw`, `reliability_index`, while a transmission line row will carry `power_flow_mw`, `losses_mw`, and possibly `voltage_kv` at its endpoints.
- The table replaces the previously separate `line_reading` and `measurement` tables, providing a single, flexible container for all time‑series telemetry.
 
### 2.3 Grid Occurrences Domain
| Table Name         | Description                                           | Estimated Volume (rows/day) | Primary Key       | Key Columns                  |
|--------------------|-------------------------------------------------------|-----------------------------|-------------------|------------------------------|
| occurrence         | Grid incidents, outages, alarms and emergency events  | ~100 events/day             | occurrence_id     | occurrence_id, ticket_number |
| occurrence_asset   | Links an occurrence to affected assets (plant, substation, line) | ~120 (avg 1.2 assets/event) | (occurrence_id, asset_type, asset_id) | occurrence_id, asset_type, asset_id |
| occurrence_type    | Reference table for occurrence classification        | ~30 (static)                | occurrence_type_id| type_code                    |
 
### 2.4 Maintenance Domain
| Table Name          | Description                                          | Estimated Volume (rows/day) | Primary Key       | Key Columns                     |
|---------------------|------------------------------------------------------|-----------------------------|-------------------|---------------------------------|
| work_order          | Preventive and corrective maintenance activities     | ~50 work orders/day         | work_order_id     | work_order_id, order_number    |
| work_order_asset    | Links a work order to affected assets                | ~60 (avg 1.2 assets/order)  | (work_order_id, asset_type, asset_id) | work_order_id, asset_type, asset_id |
| maintenance_type    | Reference table for maintenance classification       | ~20 (static)                | maintenance_type_id| type_code                       |
 
### 2.5 Asset Management Domain
| Table Name         | Description                                                  | Estimated Volume (rows/day) | Primary Key       | Key Columns                            |
|--------------------|--------------------------------------------------------------|-----------------------------|-------------------|----------------------------------------|
| asset_status       | Daily snapshot of operational status and availability per asset | ~800 (100 plants + 200 substations + 500 lines) | (snapshot_date, asset_type, asset_id) | snapshot_date, asset_type, asset_id   |
 
### 2.6 Common Reference Domain
| Table Name | Description                   | Estimated Volume | Primary Key    | Key Columns       |
|------------|-------------------------------|------------------|----------------|-------------------|
| state     | Geographical/operational regions | ~27 (static)     | state_id      | state_id, state_code |
 
*Note: `occurrence_type` and `maintenance_type` are listed in their respective domains but are essentially static reference tables.*
---
 
## 3. Entity Details
 
### 3.1 Table: plant
 
| Column Name         | Data Type     | Description                          | Business Rules / Constraints        |
|---------------------|---------------|--------------------------------------|--------------------------------------|
| plant_id            | INT (PK)      | Internal surrogate ID               | Auto-increment                       |
| plant_code          | VARCHAR(20)   | Business natural key                | Unique, stable, used as Vault hub key|
| plant_name          | VARCHAR(100)  | Name                                 | NOT NULL                             |
| plant_type          | VARCHAR(50)   | Hydro / Thermal / Wind / Solar / Nuclear | CHECK (plant_type IN list)        |
| installed_capacity  | DECIMAL(10,2) | Nameplate capacity (MW)              | > 0                                  |
| commissioning_date  | DATE          | Date plant entered operation         |                                      |
| operator_name       | VARCHAR(100)  | Operating company                    |                                      |
| status              | VARCHAR(20)   | Active / Decommissioned / Under Construction | CHECK (status IN list)         |
| last_updated  | TIMESTAMP     | Record update timestamp              | DEFAULT NOW()                        |
| estado_id           | INT (FK)      | State Acronym             | NOT NULL           |
 
**Notes for Data Vault:**
- `plant_code` becomes the business key in `hub_power_plant`.
- `plant_name`, `plant_type`, `installed_capacity`, `commissioning_date`, `operator_name` are stored in `sat_power_plant_attributes` (SCD2 for `operator_name` and `installed_capacity`).
- `status` is tracked in `sat_power_plant_status` (SCD2).
 
---
 
### 3.2 Table: generation_reading
 
| Column Name        | Data Type     | Description                                   | Business Rules                       |
|--------------------|---------------|-----------------------------------------------|--------------------------------------|
| reading_id         | BIGINT (PK)   | Surrogate key                                | Auto-increment                       |
| plant_id           | INT (FK)      | References plant(plant_id)                   | NOT NULL                             |
| reading_timestamp  | TIMESTAMP     | Measurement date/time (UTC)                  | NOT NULL, per-minute                 |
| output_mw          | DECIMAL(10,2) | Active power generated (MW)                  | >= 0                                 |
| available_capacity | DECIMAL(10,2) | Available capacity at that moment (MW)       | 0 <= available_capacity <= plant.installed_capacity |
 
**Notes for Data Vault:**
- Feeds a raw satellite `sat_gen_reading` linked to `hub_power_plant` (hash key derived from `plant_code`). The satellite stores `reading_timestamp`, `output_mw`, `available_capacity`.
- The Galaxy fact table (`Fact_Energy_Generation`) later reads from this satellite via the Business Vault or directly through a view.
 
---
 
### 3.3 Table: transmission_line
 
| Column Name            | Data Type     | Description                               | Business Rules                       |
|------------------------|---------------|-------------------------------------------|--------------------------------------|
| line_id                | INT (PK)      | Internal surrogate ID                    | Auto-increment                       |
| line_code              | VARCHAR(20)   | Business natural key                     | Unique, stable, used as Vault hub key|
| line_name              | VARCHAR(100)  | Operational name                         | NOT NULL                             |
| voltage_level_kv       | DECIMAL(6,1)  | Nominal voltage (kV)                     | > 0                                  |
| length_km              | DECIMAL(8,2)  | Line length (km)                         | > 0                                  |
| circuit_type           | VARCHAR(10)   | AC / DC                                  | CHECK (circuit_type IN ('AC','DC'))  |
| origin_substation_id   | INT (FK)      | References substation(substation_id)     | NOT NULL                             |
| destination_substation_id | INT (FK)   | References substation(substation_id)     | NOT NULL                             |
| status                 | VARCHAR(20)   | Active / Decommissioned / Planned        | CHECK (status IN list)               |
| last_updated           | TIMESTAMP     | Record update timestamp                  | DEFAULT NOW()                        |
| origin_latitude        | DECIMAL(9,6)  | Latitude of the origin substation        | NULL; -90 to 90                      |
| origin_longitude       | DECIMAL(9,6)  | Longitude of the origin substation       | NULL; -180 to 180                    |
| destination_latitude   | DECIMAL(9,6)  | Latitude of the destination substation   | NULL; -90 to 90                      |
| destination_longitude  | DECIMAL(9,6)  | Longitude of the destination substation  | NULL; -180 to 180                    |
| midpoint_latitude      | DECIMAL(9,6)  | Calculated midpoint latitude             | NULL; -90 to 90                      |
| midpoint_longitude     | DECIMAL(9,6)  | Calculated midpoint longitude            | NULL; -180 to 180              
 
**Notes for Data Vault:**
- `line_code` → `hub_transmission_line` business key.
- `line_name`, `voltage_level_kv`, `length_km`, `circuit_type`, `origin_substation_id`, `destination_substation_id` are attributes in `sat_line_attributes` (SCD2 for `voltage_level_kv`, `status`).
- `status` is also stored in a separate satellite `sat_line_status` for independent history tracking.
 
---
 
### 3.4 Table: substation
 
| Column Name        | Data Type     | Description                              | Business Rules                       |
|--------------------|---------------|------------------------------------------|--------------------------------------|
| substation_id      | INT (PK)      | Internal surrogate ID                   | Auto-increment                       |
| substation_code    | VARCHAR(20)   | Business natural key                    | Unique, stable                       |
| substation_name    | VARCHAR(100)  | Substation name                         | NOT NULL                             |
| voltage_level_kv   | DECIMAL(6,1)  | Primary voltage level (kV)              | > 0                                  |
| substation_type    | VARCHAR(30)   | Step-up / Step-down / Switching         | CHECK (substation_type IN list)      |
| status             | VARCHAR(20)   | Active / Decommissioned / Planned       | CHECK (status IN list)               |
| last_updated       | TIMESTAMP     | Record update timestamp                 | DEFAULT NOW()                        |
| stado_id          | INT (FK)      | State Acronym                           | NOT NULL                             |
 
**Notes for Data Vault:**
- `substation_code` → `hub_substation` business key.
- Attributes stored in `sat_substation_attributes` (SCD2 for `voltage_level_kv`, `status`).
- `status` also has its own satellite for independent tracking.
 
---
 
### 3.5 Table: measurement
 
*(Unified table for all time‑series telemetry from transmission lines and substations.)*
 
| Column Name        | Data Type     | Description                                          | Business Rules / Constraints                |
|--------------------|---------------|------------------------------------------------------|----------------------------------------------|
| measurement_id     | BIGINT (PK)   | Surrogate key                                        | Auto-increment                               |
| asset_type         | VARCHAR(20)   | Type of asset: 'substation' or 'transmission_line'   | NOT NULL, CHECK (asset_type IN list)          |
| asset_id           | INT           | FK to substation.substation_id or transmission_line.line_id | NOT NULL                                     |
| reading_timestamp  | TIMESTAMP     | Measurement date/time (UTC)                          | NOT NULL, per-minute                          |
| power_flow_mw      | DECIMAL(10,2) | Active power flow (MW) — only for lines              | NULL for substations; >= 0 when present       |
| losses_mw          | DECIMAL(10,2) | Transmission losses (MW) — only for lines            | NULL for substations; >= 0 when present       |
| frequency_hz       | DECIMAL(6,2)  | System frequency (Hz) — substations & lines          | 50.0 or 60.0 nominal range                   |
| voltage_kv         | DECIMAL(6,1)  | Measured voltage (kV) — substations & lines          | > 0                                           |
| system_load_mw     | DECIMAL(10,2) | Instantaneous load (MW) — typically at substations   | >= 0                                          |
| reliability_index  | DECIMAL(6,4)  | Composite reliability score (0–1)                    | 0 <= reliability_index <= 1                  |
 
**Business rules:**
- A row belongs to exactly one asset; `asset_type` + `asset_id` together identify the monitoring point.
- `power_flow_mw` and `losses_mw` are only populated when `asset_type = 'transmission_line'`; for substations these are NULL.
- `frequency_hz`, `voltage_kv`, `system_load_mw`, `reliability_index` can be populated for both types but are typical for substations and line endpoints.
- Missing readings: some minutes may be absent; the ETL only loads existing rows.
 
**Notes for Data Vault:**
- This table feeds a raw satellite `sat_measurement` in the Data Vault. The satellite stores `reading_timestamp`, `asset_type` (as part of context), and all measured values.
- The hash key for the parent entity depends on `asset_type`: it combines with `hub_substation` or `hub_transmission_line` accordingly. A link table or multi‑hub reference may be needed, but a simpler approach is to create two separate satellites: `sat_substation_measurement` and `sat_line_measurement`, each linked to the respective hub. Alternatively, a single satellite with a compound business key (asset_type + asset_id) can be used.
- Galaxy fact tables (`Fact_Energy_Transmission`, `Fact_Power_System_Monitoring`) will consume from these satellites by filtering on `asset_type`.
 
---
 
### 3.6 Table: occurrence
 
| Column Name         | Data Type     | Description                                    | Business Rules / Constraints           |
|---------------------|---------------|------------------------------------------------|----------------------------------------|
| occurrence_id       | INT (PK)      | Internal surrogate key                         | Auto-increment                         |
| ticket_number       | VARCHAR(20)   | Business natural key (work order / event ID)   | UNIQUE, NOT NULL                       |
| start_datetime      | TIMESTAMP     | Event start date/time (UTC)                    | NOT NULL                               |
| end_datetime        | TIMESTAMP     | Event resolution date/time (nullable if ongoing)|                                       |
| resolved_flag       | BOOLEAN       | Whether the occurrence is closed               | DEFAULT FALSE                          |
| affected_load_mw    | DECIMAL(10,2) | Load impacted (MW)                             | >= 0                                   |
| customers_affected  | INT           | Number of customers affected                   | >= 0                                   |
| last_updated        | TIMESTAMP     | Record update timestamp                        | DEFAULT NOW()                          |
 
**Notes for Data Vault:**
- `ticket_number` → business key for `hub_occurrence`.
- `start_datetime`, `end_datetime`, `resolved_flag`, `affected_load_mw`, `customers_affected` go into `sat_occurrence_detail` (SCD1 or SCD2 depending on update policy – usually SCD1 for mutable event data).
- The link between occurrence and affected assets is via `occurrence_asset`.
 
---
 
### 3.7 Table: occurrence_asset
 
| Column Name       | Data Type     | Description                                           | Business Rules                |
|-------------------|---------------|-------------------------------------------------------|-------------------------------|
| occurrence_id     | INT (FK)      | References occurrence(occurrence_id)                  | NOT NULL                      |
| asset_type        | VARCHAR(20)   | 'plant', 'substation', 'transmission_line'            | NOT NULL, CHECK (list)        |
| asset_id          | INT           | FK to the respective asset table (plant_id, etc.)     | NOT NULL                      |
 
**Notes for Data Vault:**
- This table materializes the many‑to‑many relationship between occurrences and assets. In Data Vault, it is modeled as a **Link table**: `link_occurrence_asset` with hash keys from `hub_occurrence`, `hub_power_plant`, `hub_substation`, `hub_transmission_line` (nullable where not applicable).
- Only the relevant hub key is populated per row; others remain NULL. Or you could use a generic Link with `asset_type` attribute, but standard Data Vault prefers separate links for each relationship. For simplicity, a single `link_occurrence_asset` with optional foreign hub keys is acceptable.
 
---
 
### 3.8 Table: occurrence_type
 
| Column Name        | Data Type     | Description                           | Business Rules                |
|--------------------|---------------|---------------------------------------|-------------------------------|
| occurrence_type_id | INT (PK)      | Surrogate key                         | Auto-increment                |
| type_code          | VARCHAR(10)   | Short code (unique)                   | UNIQUE, NOT NULL              |
| category           | VARCHAR(30)   | Outage / Equipment Failure / Alarm / Emergency | CHECK (list)         |
| subtype            | VARCHAR(50)   | Detailed classification               |                               |
| severity_level     | VARCHAR(10)   | Low / Medium / High / Critical        | CHECK (list)                  |
| date               | DATE          |                                       |                               |
 
**Notes for Data Vault:**
- Becomes a reference table in the Data Vault (or a small `dim_occurrence_type` directly in the Galaxy). Since it's static, it can be loaded as a reference table or as a satellite of a reference hub.
 
---
 
### 3.9 Table: work_order
 
| Column Name           | Data Type     | Description                                    | Business Rules                |
|-----------------------|---------------|------------------------------------------------|-------------------------------|
| work_order_id         | INT (PK)      | Internal surrogate key                         | Auto-increment                |
| order_number          | VARCHAR(20)   | Business natural key (work order number)       | UNIQUE, NOT NULL              |
| scheduled_date        | DATE          | Planned execution date                         |                               |
| planned_duration_hours| DECIMAL(6,2)  | Planned work duration                          | > 0                           |
| actual_duration_hours | DECIMAL(6,2)  | Actual work duration (nullable if not completed)| >= 0                         |
| cost                  | DECIMAL(12,2) | Maintenance cost                               | >= 0                          |
| overdue_flag          | BOOLEAN       | Whether the order is past due                  | DEFAULT FALSE                 |
| asset_availability_pct| DECIMAL(5,2)  | Asset availability during the period (%)       | 0–100                         |
| last_updated          | TIMESTAMP     | Record update timestamp                        | DEFAULT NOW()                 |
 
**Notes for Data Vault:**
- `order_number` → `hub_work_order` business key.
- All descriptive fields go into `sat_work_order_detail`.
- Relationship to assets is via `work_order_asset`.
 
---
 
### 3.10 Table: work_order_asset
 
| Column Name       | Data Type     | Description                                      | Business Rules               |
|-------------------|---------------|--------------------------------------------------|------------------------------|
| work_order_id     | INT (FK)      | References work_order(work_order_id)             | NOT NULL                     |
| asset_type        | VARCHAR(20)   | 'plant', 'substation', 'transmission_line'       | NOT NULL, CHECK (list)       |
| asset_id          | INT           | FK to the respective asset table                 | NOT NULL                     |
 
**Notes for Data Vault:**
- Link table `link_work_order_asset` connecting hubs for work order and the specific asset.
 
---
 
### 3.11 Table: maintenance_type
 
| Column Name          | Data Type     | Description                           | Business Rules                |
|----------------------|---------------|---------------------------------------|-------------------------------|
| maintenance_type_id  | INT (PK)      | Surrogate key                         | Auto-increment                |
| type_code            | VARCHAR(10)   | Short code (unique)                   | UNIQUE, NOT NULL              |
| category             | VARCHAR(20)   | Preventive / Corrective               | CHECK (list)                  |
| subtype              | VARCHAR(50)   | Inspection / Work Order / Overhaul    |                               |
| priority_level       | VARCHAR(10)   | Low / Medium / High / Urgent          | CHECK (list)                  |
 
**Notes for Data Vault:**
- Reference table; may be loaded directly into the Galaxy as a mini‑dimension, or stored as a reference table in the Data Vault.
 
---
 
### 3.12 Table: asset_status
 
| Column Name         | Data Type     | Description                                      | Business Rules               |
|---------------------|---------------|--------------------------------------------------|------------------------------|
| snapshot_date       | DATE          | Snapshot date                                    | NOT NULL                     |
| asset_type          | VARCHAR(20)   | 'plant', 'substation', 'transmission_line'       | NOT NULL, CHECK (list)       |
| asset_id            | INT           | FK to the respective asset table                 | NOT NULL                     |
| availability_pct    | DECIMAL(5,2)  | % of the day the asset was available             | 0–100                        |
| in_operation_flag   | BOOLEAN       | Whether the asset was in service that day        | DEFAULT TRUE                 |
 
**Notes for Data Vault:**
- This is a periodic snapshot. It can be loaded directly into the Galaxy fact table `Fact_Asset_Status`, or first stored as a satellite in the Data Vault (`sat_asset_status`) linked to the asset hub. For simplicity in an academic project, you might skip the Vault satellite and populate the fact table directly from this OLTP table (if the data is already clean and daily). However, to maintain architectural purity, you could create a satellite that simply stores the daily state and then the Galaxy reads from it.
 
---
 
### 3.13 Table: state
 
| Column Name        | Data Type     | Description                              | Business Rules                |
|--------------------|---------------|------------------------------------------|-------------------------------|
| state_id           | INT (PK)      | Internal surrogate key                   | Auto-increment                |
| state_code         | VARCHAR(10)   | Business natural key                     | UNIQUE, NOT NULL              |
| state_name         | VARCHAR(50)   | Region/subsystem name                    | NOT NULL                      |
| grid_operator_area | VARCHAR(50)   | ONS operational control area             |                               |
 
**Notes for Data Vault:**
- `state_id` → `hub_region` business key.
- Attributes stored in `sat_region_attributes` (static, SCD1).
 
---
 
## 4. Business Rules and Data Quality
 
### 4.1 Uniqueness and Business Keys
- **plant.plant_code** – unique, stable, used as the business key in the Data Vault.
- **transmission_line.line_code** – unique, stable.
- **substation.substation_code** – unique, stable.
- **occurrence.ticket_number** – unique; universally identifies an event.
- **work_order.order_number** – unique; identifies a work order.
- **occurrence_type.type_code** and **maintenance_type.type_code** – unique within their respective domain tables.
- **region.region_code** – unique.
 
### 4.2 Referential Integrity
- `generation_reading.plant_id` → `plant.plant_id`
- `measurement.asset_id` → `substation.substation_id` (when `asset_type = 'substation'`)  
  `measurement.asset_id` → `transmission_line.line_id` (when `asset_type = 'transmission_line'`)
- `transmission_line.origin_substation_id` → `substation.substation_id`
- `transmission_line.destination_substation_id` → `substation.substation_id`
- `occurrence_asset.occurrence_id` → `occurrence.occurrence_id`; `asset_id` points to the relevant asset table according to `asset_type`
- `work_order_asset.work_order_id` → `work_order.work_order_id`; `asset_id` points to the relevant asset table according to `asset_type`
 
### 4.3 Handling of Missing and Invalid Data
- **Generation and measurement readings**: records are expected every minute. Communication failures may cause missing minutes. The ETL process loads only the existing records; it does not fill gaps. The analytics layer may choose to interpolate or ignore missing data.
- **Null measurements**: In the `measurement` table, columns `power_flow_mw` and `losses_mw` are null for substations; other columns may be null if the monitoring point does not measure that quantity. The Data Vault preserves nulls exactly as received.
- **Dates/times**: all timestamps are in UTC. The ETL load does not perform time zone conversion.
 
### 4.4 Slowly Changing Dimensions (SCD) and History
 
- The OLTP **overwrites** master data (e.g., `operator_name`, `status`, `voltage_level_kv`). It does not maintain history on its own.
- **However**, the Data Vault is designed to capture and preserve all historical changes: during each ETL load, the current OLTP values are compared with the latest satellite records. When a change is detected, the old satellite row is closed (by setting `end_date`) and a new row is inserted, thus building a full history that the source system lacks.
- This SCD Type 2 mechanism ensures that the Galaxy dimensions (e.g., `Dim_Power_Plant`) can answer both "current state" and "as-of historical state" queries.
- For event tables (`occurrence`, `work_order`), which may be updated (e.g., closing an occurrence), the Data Vault either overwrites the corresponding satellite attributes (SCD Type 1) or keeps additional satellites for audit, depending on the project's requirements.
- **In summary:** the OLTP provides the current snapshot; the Data Vault creates and stores the complete change history needed for analytics.### 4.5 Data Volume and Growth
- **Master data tables**: `plant` (~100 records), `substation` (~200), `transmission_line` (~500), `region` (~15) – very slow growth.
- **Reading tables**: `generation_reading` (~144k rows/day), `measurement` (~1.44M rows/day) – linear growth with the number of monitoring points × minutes.
- **Event tables**: `occurrence` (~100 events/day), `work_order` (~50 orders/day) – low daily volume, but cumulative.
- **Relationship tables**: `occurrence_asset` (~120 rows/day), `work_order_asset` (~60 rows/day).
- A partitioning strategy in the Data Vault and Galaxy (by month/year) will be employed to manage the large volume of readings.

 
## 5. Entity-Relationship Overview
 
plant (1) ──────< (M) generation_reading
 
transmission_line (1) ──< (M) measurement (asset_type = 'transmission_line')
substation (1) ─────────< (M) measurement (asset_type = 'substation')
 
occurrence (1) ──< (M) occurrence_asset >── (M) asset (plant / substation / transmission_line)
work_order (1) ──< (M) work_order_asset >── (M) asset (plant / substation / transmission_line)
 
transmission_line (M) ── references ── (1) substation (origin)
transmission_line (M) ── references ── (1) substation (destination)
 
occurrence_type (independent reference table)
maintenance_type (independent reference table)
region (independent reference table, no direct FK from assets; relationships modeled in Data Vault)
 
 
**Notes:**
- The tables `measurement`, `occurrence_asset`, `work_order_asset` and `asset_status` use the pair `asset_type` + `asset_id` to dynamically reference any asset type, avoiding multiple physical foreign keys.
- The `region` table has no foreign key from the asset tables in the OLTP; the association between assets and regions is modeled in the Data Vault via link tables (e.g., `link_power_plant_region`), allowing an asset to belong to more than one region or region assignments to change over time.
- The diagram above shows the primary logical dependencies, sufficient for guiding extraction and modeling in the Data Vault.
asset_status (independent snapshot table, references assets by asset_type + asset_id)
