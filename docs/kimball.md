
Power Plant, Substation and Transmission Line act as the three "physical asset" dimensions and are shared across nearly every fact, which is what makes this a galaxy rather than a single star schema.

### 3.2 Conventions

- **Surrogate Key (SK):** sequential integer, generated during load.
- **Business Key (NK):** sourced from the Data Vault (hash_key).
- **SCD:** Slowly Changing Dimension – Type 1 (overwrite), Type 2 (new row with start/end dates), Type 3 (separate previous/current column).
- **Vault Source:** indicates which Data Vault table and column the data is extracted from. Table and column names below match the Data Vault Design Document exactly, to avoid ETL ambiguity.
- **Degenerate Dimension (DD):** an operational identifier (e.g., work order number) stored directly on the fact table with no corresponding dimension table. Degenerate dimensions use the human‑readable business key from the Hub (e.g., `ticket_number`, `order_number`), not the `hash_key_*` column, since the hash key is an internal surrogate not meant for reporting.
- **Junk Dimension:** a dimension that combines multiple low‑cardinality flags and indicators into a single table to reduce fact table width and improve manageability. Represented by `Dim_Junk_Flags`.
- **Additive measure:** can be summed across all dimensions (e.g., energy in MWh, duration, cost).
- **Semi-additive measure:** can be summed across some dimensions but not time (e.g., instantaneous power in MW, capacity, availability %).
- **Non-additive measure:** cannot be summed meaningfully under any dimension (e.g., frequency in Hz, percentages requiring context) — should be averaged or recalculated.

---

## 4. Conformed Dimensions

### 4.1 Dim_Date

*Always-present dimension. Pre-loaded for the full operational horizon.*

| Attribute      | Type    | Description                          | SCD | Vault Source / Rule       |
|----------------|---------|---------------------------------------|-----|----------------------------|
| sk_date        | INT PK  | Surrogate key                        | –   | Generated                  |
| full_date      | DATE    | Date in YYYY-MM-DD format            | –   | Date sequence               |
| year           | INT     |                                        | –   | Derived from full_date      |
| quarter        | INT     | 1–4                                    | –   | Derived from full_date      |
| month          | INT     | 1–12                                    | –   | Derived from full_date      |
| month_name     | VARCHAR |                                        | –   | Derived from full_date      |
| day            | INT     | Day of month                           | –   | Derived from full_date      |
| day_of_week    | VARCHAR |                                        | –   | Derived from full_date      |
| is_weekend     | BOOLEAN |                                        | –   | Derived from full_date      |
| holiday_flag   | BOOLEAN | National/regional holiday indicator   | 1   | Holidays reference table    |

### 4.2 Dim_Time_of_Day

*Supports the minute-level granularity required by the monitoring, generation and transmission processes. Static dimension, pre-loaded once (1,440 rows).*

| Attribute        | Type    | Description                            | SCD | Vault Source / Rule |
|------------------|---------|------------------------------------------|-----|-----------------------|
| sk_time_of_day   | INT PK  | Surrogate key (0–1439)                   | –   | Generated             |
| hour             | INT     | 0–23                                       | –   | Generated             |
| minute           | INT     | 0–59                                       | –   | Generated             |
| hh_mm            | VARCHAR | Display format, e.g. "14:35"              | –   | Generated             |
| period_of_day    | VARCHAR | Dawn / Morning / Afternoon / Night         | –   | Derived               |

> Facts at minute granularity reference **both** sk_date and sk_time_of_day.

### 4.3 Dim_Power_Plant

| Attribute              | Type     | Description                                  | SCD | Vault Source                                  |
|--------------------------|----------|-----------------------------------------------|-----|-----------------------------------------------------|
| sk_power_plant         | INT PK   | Surrogate key                                  | –   | Generated                                         |
| hash_key_power_plant   | CHAR(32) | Business key                                   | –   | hub_power_plant.hash_key_power_plant              |
| plant_name             | VARCHAR  | Plant name                                     | 1   | sat_power_plant_attributes.plant_name              |
| plant_type             | VARCHAR  | Hydro / Thermal / Wind / Solar / Nuclear         | 1   | sat_power_plant_attributes.plant_type               |
| installed_capacity_mw  | DECIMAL  | Nameplate capacity                             | 2   | sat_power_plant_attributes.installed_capacity_mw   |
| commissioning_date     | DATE     | Date plant entered operation                   | –   | sat_power_plant_attributes.commissioning_date       |
| operator_name          | VARCHAR  | Operating company                              | 2   | sat_power_plant_attributes.operator_name            |
| state_name             | VARCHAR  | State where the plant is located (denormalized)| 1   | link_power_plant_state → dim_state                  |
| status                 | VARCHAR  | Active / Decommissioned / Under Construction   | 2   | sat_power_plant_status.status                       |
| start_date             | DATE     | Validity start (SCD2)                          | 2   | Calculated during load                              |
| end_date               | DATE     | Validity end (SCD2)                            | 2   | Calculated during load                              |
| sk_state               | INT FK   | Surrogate key for state                        | –   | dim_state.sk_state (via link_power_plant_state)     |

### 4.4 Dim_Substation

| Attribute            | Type     | Description                          | SCD | Vault Source                             |
|------------------------|----------|-------------------------------------------|-----|------------------------------------------------|
| sk_substation        | INT PK   | Surrogate key                          | –   | Generated                                     |
| hash_key_substation  | CHAR(32) | Business key                           | –   | hub_substation.hash_key_substation            |
| substation_name      | VARCHAR  | Substation name                        | 1   | sat_substation_attributes.substation_name      |
| voltage_level_kv     | DECIMAL  | Primary voltage level                  | 2   | sat_substation_attributes.voltage_level_kv     |
| substation_type      | VARCHAR  | Step-up / Step-down / Switching        | 1   | sat_substation_attributes.substation_type       |
| state_name           | VARCHAR  | State where the substation is located  | 1   | link_substation_state → dim_state              |
| status               | VARCHAR  | Active / Decommissioned / Planned      | 2   | sat_substation_status.status                    |
| start_date           | DATE     | Validity start (SCD2)                  | 2   | Calculated during load                          |
| end_date             | DATE     | Validity end (SCD2)                    | 2   | Calculated during load                          |
| sk_state             | INT FK   | Surrogate key for state                | –   | dim_state.sk_state (via link_substation_state)   |

### 4.5 Dim_Transmission_Line

| Attribute              | Type     | Description                              | SCD | Vault Source                                 |
|---------------------------|----------|----------------------------------------------|-----|------------------------------------------------------|
| sk_transmission_line    | INT PK   | Surrogate key                            | –   | Generated                                         |
| hash_key_line           | CHAR(32) | Business key                             | –   | hub_transmission_line.hash_key_transmission_line   |
| line_code               | VARCHAR  | Operational line code/name               | 1   | sat_line_attributes.line_code                      |
| voltage_level_kv        | DECIMAL  | Nominal voltage                          | 2   | sat_line_attributes.voltage_level_kv               |
| length_km               | DECIMAL  | Line length                              | 1   | sat_line_attributes.length_km                      |
| circuit_type            | VARCHAR  | AC / DC                                  | 1   | sat_line_attributes.circuit_type                   |
| origin_substation_name  | VARCHAR  | Origin substation (denormalized)         | 1   | link_line_substation (role_code='ORIGIN') → dim_substation |
| destination_substation_name | VARCHAR | Destination substation (denormalized)| 1   | link_line_substation (role_code='DESTINATION') → dim_substation |
| origin_latitude         | DECIMAL(9,6) | Latitude of origin                | 1   | sat_line_attributes.origin_latitude                |
| origin_longitude        | DECIMAL(9,6) | Longitude of origin              | 1   | sat_line_attributes.origin_longitude               |
| destination_latitude    | DECIMAL(9,6) | Latitude of destination          | 1   | sat_line_attributes.destination_latitude           |
| destination_longitude   | DECIMAL(9,6) | Longitude of destination         | 1   | sat_line_attributes.destination_longitude          |
| midpoint_latitude       | DECIMAL(9,6) | Midpoint latitude                | 1   | sat_line_attributes.midpoint_latitude              |
| midpoint_longitude      | DECIMAL(9,6) | Midpoint longitude               | 1   | sat_line_attributes.midpoint_longitude             |
| status                  | VARCHAR  | Active / Decommissioned / Planned        | 2   | sat_line_status.status                              |
| start_date              | DATE     | Validity start (SCD2)                    | 2   | Calculated during load                              |
| end_date                | DATE     | Validity end (SCD2)                      | 2   | Calculated during load                              |

*Note: Dim_Transmission_Line does not include a direct state attribute because a line can span multiple states. The state for analytic purposes can be derived from the origin/destination substations via Dim_Substation during ETL, or assigned as a dominant state when building the fact tables.*

### 4.6 Dim_State

*(Replaces the former Dim_Region, aligning with the `state` table in OLTP and `hub_state`/`sat_state_attributes` in the Data Vault.)*

| Attribute          | Type     | Description                        | SCD | Vault Source                          |
|--------------------|----------|--------------------------------------|-----|------------------------------------------|
| sk_state           | INT PK   | Surrogate key                      | –   | Generated                              |
| hash_key_state     | CHAR(32) | Business key                       | –   | hub_state.hash_key_state               |
| state_code         | VARCHAR(10)| State abbreviation (UF)           | –   | hub_state.state_code (business key lives on the Hub, not on `sat_state_attributes`) |
| state_name         | VARCHAR(50)| Full state name                   | 1   | sat_state_attributes.state_name        |
| grid_operator_area | VARCHAR(50)| ONS operational control area      | 1   | sat_state_attributes.grid_operator_area |

### 4.7 Dim_Occurrence_Type

| Attribute              | Type    | Description                             | SCD | Vault Source                            |
|---------------------------|---------|------------------------------------------------|-----|------------------------------------------------|
| sk_occurrence_type      | INT PK  | Surrogate key                             | –   | Generated                                   |
| hash_key_occurrence_type| CHAR(32)| Business key                              | –   | hub_occurrence_type.hash_key_occurrence_type |
| occurrence_category     | VARCHAR | Outage / Equipment Failure / Alarm / Emergency | 1 | sat_occurrence_type_attributes.category   |
| occurrence_subtype      | VARCHAR | Specific classification                   | 1   | sat_occurrence_type_attributes.subtype     |
| severity_level          | VARCHAR | Low / Medium / High / Critical            | 1   | sat_occurrence_type_attributes.severity_level |

### 4.8 Dim_Maintenance_Type

| Attribute              | Type    | Description                          | SCD | Vault Source                          |
|---------------------------|---------|------------------------------------------|-----|------------------------------------------|
| sk_maintenance_type     | INT PK  | Surrogate key                         | –   | Generated                                 |
| hash_key_maintenance_type| CHAR(32)| Business key                          | –  | hub_maintenance_type.hash_key_maintenance_type |
| maintenance_category    | VARCHAR | Preventive / Corrective               | 1   | sat_maintenance_type_attributes.category  |
| maintenance_subtype     | VARCHAR | Inspection / Work Order / Overhaul    | 1   | sat_maintenance_type_attributes.subtype    |
| priority_level          | VARCHAR | Low / Medium / High / Urgent          | 1   | sat_maintenance_type_attributes.priority_level |

### 4.9 Dim_Junk_Flags

*Junk dimension that replaces individual low‑cardinality flags on fact tables, reducing fact table width and simplifying filter management. Each combination of flags is assigned a surrogate key. Flags that do not apply to a given fact row are set to `'N/A'`.*

| Attribute         | Type    | Description                                           | SCD | Vault Source / Rule                                                                                 |
|-------------------|---------|-------------------------------------------------------|-----|-----------------------------------------------------------------------------------------------------|
| sk_junk_flags     | INT PK  | Surrogate key                                         | –   | Generated (pre‑loaded with the 27 valid combinations)                                               |
| resolved_flag     | CHAR(3) | Occurrence resolved? `'Y'` / `'N'` / `'N/A'`           | 1   | `sat_occurrence_detail.resolved_flag` → `'Y'`/`'N'`; otherwise `'N/A'`                             |
| overdue_flag      | CHAR(3) | Work order overdue? `'Y'` / `'N'` / `'N/A'`            | 1   | `sat_work_order_detail.overdue_flag` → `'Y'`/`'N'`; otherwise `'N/A'`                              |
| in_operation_flag | CHAR(3) | Asset in service? `'Y'` / `'N'` / `'N/A'`              | 1   | `sat_*_daily_snapshot.in_operation_flag` → `'Y'`/`'N'`; otherwise `'N/A'`                          |

**Pre‑load strategy:**
The dimension is static and contains all 3³ = 27 rows. It can be re‑generated if new flag combinations become necessary (e.g., a new flag is added to the model), but that is rare.

---

## 5. Fact Tables

### 5.1 Fact_Energy_Generation

| Attribute              | Type    | Description                       | Vault Source / Rule                          |
|--------------------------|---------|--------------------------------------|-----------------------------------------------------|
| sk_date                | INT FK  | Measurement date                  | dim_date.sk_date                                 |
| sk_time_of_day         | INT FK  | Measurement minute                | dim_time_of_day.sk_time_of_day                    |
| sk_power_plant         | INT FK  | Generating plant                  | dim_power_plant.sk_power_plant (valid version at reading date) |
| sk_state               | INT FK  | State where the plant is located  | dim_state.sk_state (via dim_power_plant)          |
| generation_output_mw   | DECIMAL | Active power generated (instantaneous) | sat_gen_reading.output_mw            |
| available_capacity_mw  | DECIMAL | Capacity available at that minute | sat_gen_reading.available_capacity           |
| capacity_factor_pct    | DECIMAL | output / installed_capacity (from the plant version valid at reading date) | Calculated |

**Granularity:** One row per power plant per minute.
**Measure classification:**
- Semi-additive (cannot be summed over time): `generation_output_mw`, `available_capacity_mw`
- Non-additive: `capacity_factor_pct`
- To obtain additive energy, compute `SUM(generation_output_mw) / 60` to get megawatt-hours (MWh).

### 5.2 Fact_Energy_Transmission

| Attribute              | Type    | Description                        | Vault Source / Rule                       |
|--------------------------|---------|------------------------------------------|--------------------------------------------------|
| sk_date                | INT FK  | Measurement date                    | dim_date.sk_date                                |
| sk_time_of_day         | INT FK  | Measurement minute                  | dim_time_of_day.sk_time_of_day                   |
| sk_transmission_line   | INT FK  | Transmission line                   | dim_transmission_line.sk_transmission_line (valid version at reading date) |
| sk_state               | INT FK  | State (derived from line location – e.g., using the state of the origin substation or a predefined dominant state) | dim_state.sk_state (via ETL logic) |
| power_flow_mw          | DECIMAL | Active power flow (instantaneous)   | sat_line_measurement.power_flow_mw             |
| line_loading_pct       | DECIMAL | flow / thermal_limit                | Calculated (using line characteristics valid at reading date) |
| losses_mw              | DECIMAL | Transmission losses (instantaneous) | sat_line_measurement.losses_mw                  |

**Granularity:** One row per transmission line per minute.
**Measure classification:**
- Semi-additive: `power_flow_mw`, `losses_mw`
- Non-additive: `line_loading_pct`

*Note: The state for a transmission line fact can be determined at ETL time by choosing, for example, the state of the origin substation. This allows state-level aggregation of flows even though the line itself spans multiple states.*

### 5.3 Fact_Power_System_Monitoring

| Attribute              | Type    | Description                        | Vault Source / Rule                       |
|--------------------------|---------|------------------------------------------|--------------------------------------------------|
| sk_date                | INT FK  | Measurement date                    | dim_date.sk_date                                |
| sk_time_of_day         | INT FK  | Measurement minute                  | dim_time_of_day.sk_time_of_day                   |
| sk_substation          | INT FK  | Monitoring point (substation) – used when measurement point is a substation | dim_substation.sk_substation (nullable)          |
| sk_transmission_line   | INT FK  | Monitoring point (line) – used when measurement point is on a line | dim_transmission_line.sk_transmission_line (nullable) |
| sk_state               | INT FK  | State of the monitoring point       | dim_state.sk_state (derived from the asset: for substation via dim_substation, for line via ETL rule) |
| frequency_hz           | DECIMAL | System frequency (non-additive)     | sat_substation_measurement.frequency_hz / sat_line_measurement.frequency_hz (per row's asset type) |
| voltage_kv             | DECIMAL | Measured voltage (non-additive)     | sat_substation_measurement.voltage_kv / sat_line_measurement.voltage_kv (per row's asset type) |
| reliability_index      | DECIMAL | Composite reliability score (non-additive) | sat_substation_measurement.reliability_index (substations only; NULL for lines) |
| system_load_mw         | DECIMAL | Instantaneous system load (semi-additive) | sat_substation_measurement.system_load_mw (substations only; NULL for lines) |

**Granularity:** One row per measurement point per minute.  
**Constraint:** Exactly one of `sk_substation` or `sk_transmission_line` must be non-null; the other must be null.

**Measure classification:**
- Semi-additive: `system_load_mw`
- Non-additive: `frequency_hz`, `voltage_kv`, `reliability_index`

### 5.4 Fact_Grid_Occurrence

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|--------------------------|---------|----------------------------------------|-----------------------------------------------------|
| occurrence_id          | VARCHAR | Degenerate dimension – event/ticket ID | hub_occurrence.ticket_number (human-readable business key; not the hash_key) |
| sk_date                | INT FK  | Event start date                       | dim_date.sk_date                                    |
| sk_time_of_day         | INT FK  | Event start time                       | dim_time_of_day.sk_time_of_day                       |
| sk_power_plant         | INT FK  | Affected plant (nullable)              | link_occurrence_asset → dim_power_plant (valid version at event date) |
| sk_substation          | INT FK  | Affected substation (nullable)         | link_occurrence_asset → dim_substation                |
| sk_transmission_line   | INT FK  | Affected line (nullable)               | link_occurrence_asset → dim_transmission_line          |
| sk_state               | INT FK  | State of the affected asset            | dim_state.sk_state (derived from the asset)           |
| sk_occurrence_type     | INT FK  | Type/category/severity                 | dim_occurrence_type.sk_occurrence_type                 |
| sk_junk_flags          | INT FK  | Junk dimension for flags               | dim_junk_flags.sk_junk_flags (resolved_flag = 'Y'/'N', overdue_flag = 'N/A', in_operation_flag = 'N/A') |
| duration_minutes       | DECIMAL | Time to resolution                     | sat_occurrence_detail.duration_minutes                  |
| affected_load_mw       | DECIMAL | Load impacted                          | sat_occurrence_detail.affected_load_mw                   |
| customers_affected     | INT     | Customers impacted                     | sat_occurrence_detail.customers_affected                 |

**Granularity:** One row per occurrence event per affected asset. If an occurrence affects multiple assets, it is split into multiple rows, each with a single non-null asset FK.  
**Measure classification:**
- Additive: `duration_minutes`, `affected_load_mw`, `customers_affected`

### 5.5 Fact_Maintenance

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|--------------------------|---------|----------------------------------------|-----------------------------------------------------|
| work_order_number      | VARCHAR | Degenerate dimension – work order ID    | hub_work_order.order_number (human-readable business key; not the hash_key) |
| sk_date                | INT FK  | Scheduled/executed date                | dim_date.sk_date                                    |
| sk_power_plant         | INT FK  | Asset under maintenance (nullable)     | link_work_order_asset → dim_power_plant (valid version at date) |
| sk_substation          | INT FK  | Asset under maintenance (nullable)     | link_work_order_asset → dim_substation               |
| sk_transmission_line   | INT FK  | Asset under maintenance (nullable)     | link_work_order_asset → dim_transmission_line         |
| sk_state               | INT FK  | State of the asset                     | dim_state.sk_state (derived from the asset)           |
| sk_maintenance_type    | INT FK  | Category/subtype/priority              | dim_maintenance_type.sk_maintenance_type                |
| sk_junk_flags          | INT FK  | Junk dimension for flags               | dim_junk_flags.sk_junk_flags (overdue_flag = 'Y'/'N', resolved_flag = 'N/A', in_operation_flag = 'N/A') |
| planned_duration_hours | DECIMAL | Planned work duration                  | sat_work_order_detail.planned_duration_hours            |
| actual_duration_hours  | DECIMAL | Actual work duration                   | sat_work_order_detail.actual_duration_hours              |
| cost                   | DECIMAL | Maintenance cost                       | sat_work_order_detail.cost                              |
| asset_availability_pct | DECIMAL | Asset availability during the period   | sat_work_order_detail.asset_availability_pct                |

**Granularity:** One row per maintenance activity per asset. If a single work order covers multiple assets, it generates multiple rows (one per asset).  
**Measure classification:**
- Additive: `planned_duration_hours`, `actual_duration_hours`, `cost`
- Semi-additive: `asset_availability_pct`

### 5.6 Fact_Asset_Status

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|--------------------------|---------|----------------------------------------|-----------------------------------------------------|
| sk_date                | INT FK  | Snapshot date                          | dim_date.sk_date                                    |
| sk_power_plant         | INT FK  | Asset (nullable)                       | dim_power_plant.sk_power_plant (valid version at snapshot date) |
| sk_substation          | INT FK  | Asset (nullable)                       | dim_substation.sk_substation (valid version)        |
| sk_transmission_line   | INT FK  | Asset (nullable)                       | dim_transmission_line.sk_transmission_line (valid version) |
| sk_state               | INT FK  | State of the asset                     | dim_state.sk_state (derived from the asset)          |
| sk_junk_flags          | INT FK  | Junk dimension for flags               | dim_junk_flags.sk_junk_flags (in_operation_flag = 'Y'/'N', resolved_flag = 'N/A', overdue_flag = 'N/A') |
| availability_pct       | DECIMAL | % of the day the asset was available   | sat_power_plant_daily_snapshot.availability_pct / sat_substation_daily_snapshot.availability_pct / sat_line_daily_snapshot.availability_pct (per row's asset type) |
| asset_age_years        | DECIMAL | Age since commissioning                | Calculated (snapshot_date − commissioning_date from the valid dimension row); also available pre-calculated on the source snapshot satellites |

**Granularity:** One row per physical asset per day. Exactly one of the asset FKs is non-null.  
**Measure classification:**
- Semi-additive: `availability_pct`
- Non-additive: `asset_age_years`

---

## 6. Glossary and Metadata

| Term                  | Definition                                                                                  | Owner      |
|-----------------------|----------------------------------------------------------------------------------------------|------------|
| ONS                   | Operador Nacional do Sistema Elétrico – Brazilian ISO                                         | Operations |
| Active Power (MW)     | Instantaneous electric power flow                                                            | Engineering|
| Energy (MWh)          | Integrated power over time, computed as AVG(MW) * hours                                      | Analytics  |
| Capacity Factor       | Ratio of actual generation to maximum possible generation (nameplate capacity × time)        | Engineering|
| SCD2                  | Slowly Changing Dimension Type 2 – preserves history by creating a new row                   | Data       |
| Degenerate Dimension  | Transactional identifier stored directly on the fact table (e.g., work order number)         | Data       |
| Junk Dimension        | Dimension combining low‑cardinality flags/indicators to simplify fact tables                 | Data       |
| Galaxy Schema         | A dimensional model with multiple fact tables sharing conformed dimensions                   | Data       |

---

## 7. Performance and Security

- **Indexes:** create B-tree indexes on all foreign keys in fact tables; bitmap indexes on frequently filtered dimension columns (e.g., `state_name`, `status`).
- **Partitioning:** partition fact tables by `sk_date` (year-month) to improve manageability and query performance.
- **Aggregations:** consider building aggregate tables for common rollups (e.g., daily generation per plant per state, monthly outages per state) to accelerate dashboards.
- **Row-Level Security (RLS):** if needed, apply filters on `dim_state` to restrict data access by operational area.

---

## 8. Revisions

| Version | Date       | Changes                                                                                                                      | Author           |
|---------|------------|------------------------------------------------------------------------------------------------------------------------------|------------------|
| 1.0     | 07/21/2026 | Initial document creation                                                                                                    | Guilherme Roriz  |
| 1.1     | 07/21/2026 | Refined measure classification, corrected fact granularity notes                                                             | Guilherme Roriz  |
| 1.2     | 07/21/2026 | Corrected SCD2 join logic in ETL, clarified measure additivity, added glossary, partitioning section                         | Guilherme Roriz  |
| 1.3     | 07/23/2026 | Replaced Dim_Region with Dim_State, updated all dimensions and facts accordingly, added geographic coordinates to transmission line dimension | Guilherme Roriz  |
| 1.4     | 07/23/2026 | Review pass, aligned all "Vault Source" references with actual Data Vault table/column names; corrected satellite column names; added business key attributes to Dim_Occurrence_Type/Dim_Maintenance_Type; fixed Dim_State.state_code source; changed degenerate dimensions to human-readable business keys | Guilherme Roriz  |
| 1.5     | 07/24/2026 | Introduced Dim_Junk_Flags to replace individual boolean flags on fact tables; adjusted Fact_Grid_Occurrence, Fact_Maintenance, Fact_Asset_Status to reference the junk dimension; added Junk Flags column to bus matrix | Guilherme Roriz  |
