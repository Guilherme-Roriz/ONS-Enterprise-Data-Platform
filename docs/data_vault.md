# Data Vault Design Document

**Project:** ONS Enterprise Data Platform  
**Layer:** Enterprise Data Warehouse (Data Vault)  
**Data Source:** OLTP (PostgreSQL)  
**Author:** Guilherme Roriz  
**Date:** 24/07/2026  
**Version:** 1.1

---

## 1. Data Vault Overview

This document describes the **Raw Data Vault** for the ONS Enterprise Data Platform. The Data Vault is the central integration layer that receives data directly from the OLTP system and serves as the single source of truth for the downstream dimensional layer. It is designed following Data Vault 2.0 principles: separation of business keys (Hubs), relationships (Links), and descriptive attributes with full history (Satellites).

All structured data from the OLTP is ingested into the Raw Vault. The Data Lake is used only for unstructured/semi‑structured data and is not covered here.

---

## 2. Design Conventions

| Convention        | Value / Rule                                                                 |
|-------------------|------------------------------------------------------------------------------|
| Hash algorithm    | SHA‑256, stored as CHAR(64) (hexadecimal)                                    |
| Business key      | The column(s) that uniquely identify a business object in the source system (e.g., `plant_code`, `line_code`). Used to generate the hash key. |
| Hash key column   | `hash_key_<entity>` (e.g., `hash_key_power_plant`)                            |
| Load date         | `load_date TIMESTAMP` – the moment the record was inserted into the Vault     |
| Record source     | `record_source VARCHAR(50)` – identifies the source system (e.g., `'ONS_OLTP'`) |
| Hub naming        | `hub_<business_entity>` (e.g., `hub_power_plant`)                              |
| Link naming       | `link_<relationship>` (e.g., `link_occurrence_power_plant`)                    |
| Satellite naming  | `sat_<parent>_<descriptor>` (e.g., `sat_power_plant_attributes`)               |
| Parent key        | The hash key of the parent Hub (for Satellites on Hubs) or the hash key of the parent Link (for Satellites on Links) |
| Hash diff         | `hash_diff CHAR(64)` – SHA‑256 of all descriptive columns (for change detection)  |
| End dating        | For SCD2 Satellites, `start_date` and `end_date` track validity                |
| Load strategy     | Insert‑only; Satellites receive a new row when a hash diff change is detected  |

---

## 3. Hubs

### 3.1 Hub – Power Plant
| Column                  | Type     | Description                        |
|-------------------------|----------|------------------------------------|
| hash_key_power_plant    | CHAR(64) PK | SHA‑256(`plant_code`)             |
| plant_code              | VARCHAR(20) | Business natural key               |
| load_date               | TIMESTAMP   | First time seen in the Vault       |
| record_source           | VARCHAR(50) | `'ONS_OLTP'`                       |

### 3.2 Hub – Transmission Line
| Column                      | Type     | Description                        |
|-----------------------------|----------|------------------------------------|
| hash_key_transmission_line  | CHAR(64) PK | SHA‑256(`line_code`)              |
| line_code                   | VARCHAR(20) | Business natural key               |
| load_date                   | TIMESTAMP   |                                    |
| record_source               | VARCHAR(50) |                                    |

### 3.3 Hub – Substation
| Column              | Type     | Description                        |
|---------------------|----------|------------------------------------|
| hash_key_substation | CHAR(64) PK | SHA‑256(`substation_code`)        |
| substation_code     | VARCHAR(20) | Business natural key               |
| load_date           | TIMESTAMP   |                                    |
| record_source       | VARCHAR(50) |                                    |

### 3.4 Hub – Occurrence
| Column                 | Type     | Description                        |
|------------------------|----------|------------------------------------|
| hash_key_occurrence    | CHAR(64) PK | SHA‑256(`ticket_number`)          |
| ticket_number          | VARCHAR(20) | Business natural key (event ID)   |
| load_date              | TIMESTAMP   |                                    |
| record_source          | VARCHAR(50) |                                    |

### 3.5 Hub – Work Order
| Column                 | Type     | Description                        |
|------------------------|----------|------------------------------------|
| hash_key_work_order    | CHAR(64) PK | SHA‑256(`order_number`)          |
| order_number           | VARCHAR(20) | Business natural key               |
| load_date              | TIMESTAMP   |                                    |
| record_source          | VARCHAR(50) |                                    |

### 3.6 Hub – State
| Column          | Type     | Description                        |
|-----------------|----------|------------------------------------|
| hash_key_state  | CHAR(64) PK | SHA‑256(`state_code`)             |
| state_code      | VARCHAR(10) | Business natural key (UF)          |
| load_date       | TIMESTAMP   |                                    |
| record_source   | VARCHAR(50) |                                    |

### 3.7 Hub – Occurrence Type
| Column                    | Type     | Description                        |
|---------------------------|----------|------------------------------------|
| hash_key_occurrence_type  | CHAR(64) PK | SHA‑256(`type_code`)             |
| type_code                 | VARCHAR(10) | Business natural key               |
| load_date                 | TIMESTAMP   |                                    |
| record_source             | VARCHAR(50) |                                    |

### 3.8 Hub – Maintenance Type
| Column                    | Type     | Description                        |
|---------------------------|----------|------------------------------------|
| hash_key_maintenance_type | CHAR(64) PK | SHA‑256(`type_code`)             |
| type_code                 | VARCHAR(10) | Business natural key               |
| load_date                 | TIMESTAMP   |                                    |
| record_source             | VARCHAR(50) |                                    |

---

## 4. Links

### 4.1 Link – Occurrence to Power Plant
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_occ_plant     | CHAR(64) PK | SHA‑256(`hash_key_occurrence` + `hash_key_power_plant`) |
| hash_key_occurrence         | CHAR(64) FK | References `hub_occurrence`                         |
| hash_key_power_plant        | CHAR(64) FK | References `hub_power_plant`                        |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

### 4.2 Link – Occurrence to Substation
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_occ_sub       | CHAR(64) PK | SHA‑256(`hash_key_occurrence` + `hash_key_substation`) |
| hash_key_occurrence         | CHAR(64) FK |                                                     |
| hash_key_substation         | CHAR(64) FK |                                                     |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

### 4.3 Link – Occurrence to Transmission Line
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_occ_line      | CHAR(64) PK | SHA‑256(`hash_key_occurrence` + `hash_key_transmission_line`) |
| hash_key_occurrence         | CHAR(64) FK |                                                     |
| hash_key_transmission_line  | CHAR(64) FK |                                                     |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

### 4.4 Link – Work Order to Power Plant
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_wo_plant      | CHAR(64) PK | SHA‑256(`hash_key_work_order` + `hash_key_power_plant`) |
| hash_key_work_order         | CHAR(64) FK | References `hub_work_order`                         |
| hash_key_power_plant        | CHAR(64) FK |                                                     |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

### 4.5 Link – Work Order to Substation
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_wo_sub        | CHAR(64) PK | SHA‑256(`hash_key_work_order` + `hash_key_substation`) |
| hash_key_work_order         | CHAR(64) FK |                                                     |
| hash_key_substation         | CHAR(64) FK |                                                     |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

### 4.6 Link – Work Order to Transmission Line
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_wo_line       | CHAR(64) PK | SHA‑256(`hash_key_work_order` + `hash_key_transmission_line`) |
| hash_key_work_order         | CHAR(64) FK |                                                     |
| hash_key_transmission_line  | CHAR(64) FK |                                                     |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

### 4.7 Link – Power Plant to State
| Column                    | Type     | Description                         |
|---------------------------|----------|-------------------------------------|
| hash_key_link_plant_state | CHAR(64) PK | SHA‑256(`hash_key_power_plant` + `hash_key_state`) |
| hash_key_power_plant      | CHAR(64) FK |                                     |
| hash_key_state            | CHAR(64) FK |                                     |
| load_date                 | TIMESTAMP   |                                     |
| record_source             | VARCHAR(50) |                                     |

### 4.8 Link – Substation to State
| Column                        | Type     | Description                             |
|-------------------------------|----------|-----------------------------------------|
| hash_key_link_substation_state| CHAR(64) PK | SHA‑256(`hash_key_substation` + `hash_key_state`) |
| hash_key_substation           | CHAR(64) FK |                                         |
| hash_key_state                | CHAR(64) FK |                                         |
| load_date                     | TIMESTAMP   |                                         |
| record_source                 | VARCHAR(50) |                                         |

### 4.9 Link – Transmission Line to Substation (Roles)
| Column                      | Type     | Description                                         |
|-----------------------------|----------|-----------------------------------------------------|
| hash_key_link_line_sub      | CHAR(64) PK | SHA‑256(`hash_key_transmission_line` + `hash_key_substation` + `role_code`) |
| hash_key_transmission_line  | CHAR(64) FK | References `hub_transmission_line`                 |
| hash_key_substation         | CHAR(64) FK | References `hub_substation`                         |
| role_code                   | VARCHAR(20) | `'ORIGIN'` or `'DESTINATION'`                      |
| load_date                   | TIMESTAMP   |                                                     |
| record_source               | VARCHAR(50) |                                                     |

---

## 5. Satellites

### 5.1 Satellites on Hub – Power Plant

#### 5.1.1 `sat_power_plant_attributes`
Captures descriptive attributes. SCD2 on `operator_name` and `installed_capacity_mw`.

| Column                   | Type          | Description                              |
|--------------------------|---------------|------------------------------------------|
| hash_key_power_plant     | CHAR(64) FK   | References `hub_power_plant`             |
| start_date               | DATE          | Validity start (inclusive)               |
| end_date                 | DATE          | Validity end (exclusive, NULL = current) |
| plant_name               | VARCHAR(100)  |                                          |
| plant_type               | VARCHAR(50)   |                                          |
| installed_capacity_mw    | DECIMAL(10,2) |                                          |
| commissioning_date       | DATE          |                                          |
| operator_name            | VARCHAR(100)  |                                          |
| hash_diff                | CHAR(64)      | For change detection                     |
| load_date                | TIMESTAMP     |                                          |
| record_source            | VARCHAR(50)   |                                          |

*Composite primary key: (hash_key_power_plant, start_date)*

#### 5.1.2 `sat_power_plant_status`
Tracks the operational status independently. SCD2.

| Column                | Type         | Description                              |
|-----------------------|--------------|------------------------------------------|
| hash_key_power_plant  | CHAR(64) FK  |                                          |
| start_date            | DATE         | Validity start                            |
| end_date              | DATE         | Validity end (NULL = current)             |
| status                | VARCHAR(20)  | Active / Decommissioned / Under Construction |
| hash_diff             | CHAR(64)     |                                          |
| load_date             | TIMESTAMP    |                                          |
| record_source         | VARCHAR(50)  |                                          |

#### 5.1.3 `sat_power_plant_daily_snapshot`
Periodic daily snapshot (from `asset_status` table). Insert‑only, no SCD2.

| Column                | Type         | Description                              |
|-----------------------|--------------|------------------------------------------|
| hash_key_power_plant  | CHAR(64) FK  |                                          |
| snapshot_date         | DATE         | Day of the snapshot                      |
| availability_pct      | DECIMAL(5,2) |                                          |
| in_operation_flag     | BOOLEAN      |                                          |
| load_date             | TIMESTAMP    |                                          |
| record_source         | VARCHAR(50)  |                                          |

*Composite key: (hash_key_power_plant, snapshot_date). Only one row per asset per day; new loads can overwrite if necessary (upsert).*

### 5.2 Satellites on Hub – Transmission Line

#### 5.2.1 `sat_line_attributes`
SCD2 on `voltage_level_kv`, and also contains static attributes and geographic coordinates.

| Column                      | Type          | Description                              |
|-----------------------------|---------------|------------------------------------------|
| hash_key_transmission_line  | CHAR(64) FK   |                                          |
| start_date                  | DATE          | Validity start                            |
| end_date                    | DATE          | Validity end (NULL = current)             |
| line_code                   | VARCHAR(20)   | Operational code (denormalized for ease) |
| voltage_level_kv            | DECIMAL(6,1)  | SCD2                                     |
| length_km                   | DECIMAL(8,2)  |                                          |
| circuit_type                | VARCHAR(10)   | AC / DC                                  |
| origin_latitude             | DECIMAL(9,6)  |                                          |
| origin_longitude            | DECIMAL(9,6)  |                                          |
| destination_latitude        | DECIMAL(9,6)  |                                          |
| destination_longitude       | DECIMAL(9,6)  |                                          |
| midpoint_latitude           | DECIMAL(9,6)  |                                          |
| midpoint_longitude          | DECIMAL(9,6)  |                                          |
| hash_diff                   | CHAR(64)      |                                          |
| load_date                   | TIMESTAMP     |                                          |
| record_source               | VARCHAR(50)   |                                          |

*Composite PK: (hash_key_transmission_line, start_date)*

#### 5.2.2 `sat_line_status`
Tracks operational status of the line. SCD2.

| Column                      | Type         | Description                              |
|-----------------------------|--------------|------------------------------------------|
| hash_key_transmission_line  | CHAR(64) FK  |                                          |
| start_date                  | DATE         |                                          |
| end_date                    | DATE         |                                          |
| status                      | VARCHAR(20)  | Active / Decommissioned / Planned        |
| hash_diff                   | CHAR(64)     |                                          |
| load_date                   | TIMESTAMP    |                                          |
| record_source               | VARCHAR(50)  |                                          |

#### 5.2.3 `sat_line_daily_snapshot`
Daily operational snapshot (from `asset_status`). Insert‑only.

| Column                      | Type         | Description |
|-----------------------------|--------------|-------------|
| hash_key_transmission_line  | CHAR(64) FK  |             |
| snapshot_date               | DATE         |             |
| availability_pct            | DECIMAL(5,2) |             |
| in_operation_flag           | BOOLEAN      |             |
| load_date                   | TIMESTAMP    |             |
| record_source               | VARCHAR(50)  |             |

*Composite key: (hash_key_transmission_line, snapshot_date)*

### 5.3 Satellites on Hub – Substation

#### 5.3.1 `sat_substation_attributes`
SCD2 on `voltage_level_kv`.

| Column              | Type          | Description |
|---------------------|---------------|-------------|
| hash_key_substation | CHAR(64) FK   |             |
| start_date          | DATE          |             |
| end_date            | DATE          |             |
| substation_name     | VARCHAR(100)  |             |
| voltage_level_kv    | DECIMAL(6,1)  | SCD2        |
| substation_type     | VARCHAR(30)   |             |
| hash_diff           | CHAR(64)      |             |
| load_date           | TIMESTAMP     |             |
| record_source       | VARCHAR(50)   |             |

#### 5.3.2 `sat_substation_status`
SCD2 on `status`.

| Column              | Type         | Description |
|---------------------|--------------|-------------|
| hash_key_substation | CHAR(64) FK  |             |
| start_date          | DATE         |             |
| end_date            | DATE         |             |
| status              | VARCHAR(20)  |             |
| hash_diff           | CHAR(64)     |             |
| load_date           | TIMESTAMP    |             |
| record_source       | VARCHAR(50)  |             |

#### 5.3.3 `sat_substation_daily_snapshot`
Daily snapshot (from `asset_status`).

| Column              | Type         | Description |
|---------------------|--------------|-------------|
| hash_key_substation | CHAR(64) FK  |             |
| snapshot_date       | DATE         |             |
| availability_pct    | DECIMAL(5,2) |             |
| in_operation_flag   | BOOLEAN      |             |
| load_date           | TIMESTAMP    |             |
| record_source       | VARCHAR(50)  |             |

### 5.4 Satellites on Hub – Occurrence

#### 5.4.1 `sat_occurrence_detail`
Stores mutable event data. For simplicity, SCD1 overwrite is used; historical audit may require a separate satellite.

| Column                    | Type          | Description                              |
|---------------------------|---------------|------------------------------------------|
| hash_key_occurrence       | CHAR(64) FK   |                                          |
| hash_key_occurrence_type  | CHAR(64) FK   | References `hub_occurrence_type`         |
| start_datetime            | TIMESTAMP     | Event start (from OLTP)                  |
| end_datetime              | TIMESTAMP     | Event resolution (nullable if ongoing)   |
| resolved_flag             | BOOLEAN       |                                          |
| affected_load_mw          | DECIMAL(10,2) |                                          |
| customers_affected        | INT           |                                          |
| duration_minutes          | DECIMAL       | (can be derived, but stored for convenience) |
| hash_diff                 | CHAR(64)      |                                          |
| load_date                 | TIMESTAMP     |                                          |
| record_source             | VARCHAR(50)   |                                          |

*Because occurrences may be updated, the ETL loads the latest state and closes the previous row only if full SCD2 is required. The hash_key_occurrence_type is taken from the OLTP FK via a lookup to `hub_occurrence_type`.*

### 5.5 Satellites on Hub – Work Order

#### 5.5.1 `sat_work_order_detail`
Similar to occurrence; includes the reference to maintenance type.

| Column                   | Type          | Description |
|--------------------------|---------------|-------------|
| hash_key_work_order      | CHAR(64) FK   |             |
| hash_key_maintenance_type| CHAR(64) FK   | References `hub_maintenance_type` |
| scheduled_date           | DATE          |             |
| planned_duration_hours   | DECIMAL(6,2)  |             |
| actual_duration_hours    | DECIMAL(6,2)  |             |
| cost                     | DECIMAL(12,2) |             |
| overdue_flag             | BOOLEAN       |             |
| asset_availability_pct   | DECIMAL(5,2)  |             |
| hash_diff                | CHAR(64)      |             |
| load_date                | TIMESTAMP     |             |
| record_source            | VARCHAR(50)   |             |

### 5.6 Satellites on Hub – State

#### 5.6.1 `sat_state_attributes`
Static reference data (SCD1).

| Column              | Type         | Description |
|---------------------|--------------|-------------|
| hash_key_state      | CHAR(64) FK  |             |
| state_name          | VARCHAR(50)  |             |
| ons_control_area    | VARCHAR(50)  | ONS operational control area |
| hash_diff           | CHAR(64)     |             |
| load_date           | TIMESTAMP    |             |
| record_source       | VARCHAR(50)  |             |

### 5.7 Satellites on Hub – Occurrence Type

#### 5.7.1 `sat_occurrence_type_attributes`
Reference data (SCD1).

| Column                    | Type         | Description |
|---------------------------|--------------|-------------|
| hash_key_occurrence_type  | CHAR(64) FK  |             |
| category                  | VARCHAR(30)  |             |
| subtype                   | VARCHAR(50)  |             |
| severity_level            | VARCHAR(10)  |             |
| hash_diff                 | CHAR(64)     |             |
| load_date                 | TIMESTAMP    |             |
| record_source             | VARCHAR(50)  |             |

### 5.8 Satellites on Hub – Maintenance Type

#### 5.8.1 `sat_maintenance_type_attributes`
Reference data (SCD1).

| Column                    | Type         | Description |
|---------------------------|--------------|-------------|
| hash_key_maintenance_type | CHAR(64) FK  |             |
| category                  | VARCHAR(20)  |             |
| subtype                   | VARCHAR(50)  |             |
| priority_level            | VARCHAR(10)  |             |
| hash_diff                 | CHAR(64)     |             |
| load_date                 | TIMESTAMP    |             |
| record_source             | VARCHAR(50)  |             |

### 5.9 Raw Transaction Satellites (Insert‑Only)

These satellites capture measurement/reading data without any update logic. They are the raw source for downstream analytics.

#### 5.9.1 `sat_gen_reading`
Linked to `hub_power_plant`.

| Column                | Type          | Description                       |
|-----------------------|---------------|-----------------------------------|
| hash_key_power_plant  | CHAR(64) FK   |                                   |
| reading_timestamp     | TIMESTAMP     | UTC per‑minute                    |
| generation_output_mw  | DECIMAL(10,2) |                                   |
| available_capacity_mw | DECIMAL(10,2) |                                   |
| load_date             | TIMESTAMP     | When loaded into Vault            |
| record_source         | VARCHAR(50)   |                                   |

*No hash_diff because this satellite is append‑only; each reading is a new row.*

#### 5.9.2 `sat_substation_measurement`
Linked to `hub_substation`; receives rows from `measurement` where `asset_type = 'substation'`.

| Column              | Type          | Description                     |
|---------------------|---------------|---------------------------------|
| hash_key_substation | CHAR(64) FK   |                                 |
| reading_timestamp   | TIMESTAMP     |                                 |
| frequency_hz        | DECIMAL(6,2)  |                                 |
| voltage_kv          | DECIMAL(6,1)  |                                 |
| system_load_mw      | DECIMAL(10,2) |                                 |
| reliability_index   | DECIMAL(6,4)  |                                 |
| load_date           | TIMESTAMP     |                                 |
| record_source       | VARCHAR(50)   |                                 |

*Append‑only.*

#### 5.9.3 `sat_line_measurement`
Linked to `hub_transmission_line`; receives rows from `measurement` where `asset_type = 'transmission_line'`.

| Column                      | Type          | Description |
|-----------------------------|---------------|-------------|
| hash_key_transmission_line  | CHAR(64) FK   |             |
| reading_timestamp           | TIMESTAMP     |             |
| power_flow_mw               | DECIMAL(10,2) |             |
| losses_mw                   | DECIMAL(10,2) |             |
| frequency_hz                | DECIMAL(6,2)  |             |
| voltage_kv                  | DECIMAL(6,1)  |             |
| load_date                   | TIMESTAMP     |             |
| record_source               | VARCHAR(50)   |             |

*Append‑only.*

**Design rationale for measurement split:** The OLTP `measurement` table uses `asset_type` to distinguish between substations and lines. In the Raw Vault, we split this into two separate satellites to maintain a strict 1:1 relationship between each satellite and its parent hub. The downstream Galaxy fact table later combines them via UNION when building a unified monitoring view. This approach adheres to Data Vault 2.0 best practices and avoids polymorphic satellites.

---

## 6. ETL Mapping Summary (OLTP → Raw Data Vault)

| OLTP Table               | Target Hub/Link/Satellite(s)                                                                                           |
|---------------------------|------------------------------------------------------------------------------------------------------------------------|
| plant                     | `hub_power_plant`, `sat_power_plant_attributes`, `sat_power_plant_status`, `link_power_plant_state`                    |
| generation_reading        | `sat_gen_reading` (using `hub_power_plant` hash)                                                                       |
| transmission_line         | `hub_transmission_line`, `sat_line_attributes`, `sat_line_status`, `link_transmission_line_substation` (2 rows: origin & destination) |
| substation                | `hub_substation`, `sat_substation_attributes`, `sat_substation_status`, `link_substation_state`                        |
| measurement               | `sat_substation_measurement` (for substation rows), `sat_line_measurement` (for line rows)                             |
| occurrence                | `hub_occurrence`, `sat_occurrence_detail` (includes `hash_key_occurrence_type`)                                        |
| occurrence_asset          | `link_occurrence_power_plant` / `link_occurrence_substation` / `link_occurrence_transmission_line` (depending on asset_type) |
| occurrence_type           | `hub_occurrence_type`, `sat_occurrence_type_attributes`                                                                |
| work_order                | `hub_work_order`, `sat_work_order_detail` (includes `hash_key_maintenance_type`)                                       |
| work_order_asset          | `link_work_order_power_plant` / `link_work_order_substation` / `link_work_order_transmission_line`                     |
| maintenance_type          | `hub_maintenance_type`, `sat_maintenance_type_attributes`                                                              |
| asset_status              | `sat_power_plant_daily_snapshot`, `sat_substation_daily_snapshot`, `sat_line_daily_snapshot` (split by `asset_type`)    |
| state                     | `hub_state`, `sat_state_attributes`                                                                                    |

All loads are incremental, using timestamps or CDC from the OLTP. Master data tables are compared via hash_diff to detect changes and generate new satellite rows with appropriate end‑dating.

---

## 7. Revision History

| Version | Date       | Changes                                                                                              | Author           |
|---------|------------|------------------------------------------------------------------------------------------------------|------------------|
| 1.0     | 23/07/2026 | Initial Raw Data Vault design                                                                        | Guilherme Roriz  |
| 1.1     | 24/07/2026 | Replaced polymorphic links with separate links per asset type; switched to SHA‑256 hashing; removed Galaxy‑specific consumption notes; removed `asset_age_years` from satellites; added `hash_key_occurrence_type` and `hash_key_maintenance_type` to respective satellites; renamed `link_line_substation` to `link_transmission_line_substation`; adjusted ETL mapping and added measurement split rationale | Guilherme Roriz  |
