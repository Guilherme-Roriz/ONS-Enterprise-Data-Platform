# Dimensional Modeling Document – Kimball

**Project:** ONS Enterprise Data Platform
**Layer:** Galaxy Schema (Analytics)
**Data Source:** Data Vault (Enterprise Data Warehouse)
**Author:** Guilherme Roriz
**Date:** 24/07/2026
**Version:** 1.6

---

## 0. Architecture Overview (Optional)

[SCADA/ERP/Maintenance]
│
▼
OLTP (PostgreSQL)
│
▼
CDC (Change Data Capture)
│
▼
Raw Data Vault (Integration)
│
▼
Business Vault (PITs, Bridges, derived logic)
│
▼
Galaxy Schema (Dimensional Analytics)
│
▼
BI Layer (Power BI, etc.)


---

## 1. Business Requirements and Scope

### 1.1 Measured Business Processes

| Business Process                             | Description                                                                                                     |
|-----------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| Power System Monitoring and Performance        | Monitors system-wide indicators such as frequency, voltage, reliability and overall grid performance.             |
| Energy Generation                              | Monitors electricity production from power plants, including generation output, capacity and availability.       |
| Energy Transmission                            | Monitors the transmission network, tracking power flows, installations and emergency incidents.                  |
| Grid Occurrences                               | Records, monitors and resolves outages, equipment failures, alarms and emergency incidents.                       |
| Maintenance Monitoring                         | Tracks preventive and corrective maintenance activities, inspections, work orders and asset availability.         |
| Asset Management                               | Maintains information about power system assets, including power plants, substations and transmission lines.     |

### 1.2 Key Analytical Questions

- How much energy is each power plant generating?
- Which plants have the highest and lowest generation?
- What is the generation trend over time?
- Which transmission lines carry the highest power flow?
- Which substations are the most critical?
- Where are transmission bottlenecks occurring?
- What are the most frequent occurrence types?
- What is the average outage duration?
- How many maintenance activities are overdue?
- Which assets have the lowest availability?
- Is the system frequency within operational limits?
- How stable is the electrical grid over time?
- How many assets are in operation?

### 1.3 Defined Granularities

- **Power System Monitoring and Performance:** One record per measurement point per minute (point belongs to either a substation or a transmission line).
- **Energy Generation:** One record per power plant per minute.
- **Energy Transmission:** One record per transmission line per minute.
- **Grid Occurrences:** One record per occurrence event. If an occurrence affects multiple assets, the event is repeated once per affected asset (each row corresponds to exactly one affected asset).
- **Maintenance Monitoring:** One record per maintenance activity per asset.
- **Asset Management:** One record per physical asset per day (status snapshot).

---

## 2. Bus Matrix

| Business Process                           | DateTime | Power Plant | Substation | Transmission Line | State | Occurrence | Maintenance | Junk Flags |
|---------------------------------------------|:--------:|:-----------:|:----------:|:------------------:|:-----:|:----------:|:-----------:|:----------:|
| **Energy Generation**                       |    ✓     |      ✓      |            |                    |   ✓   |            |             |            |
| **Energy Transmission**                     |    ✓     |             |     ✓      |         ✓          |   ✓   |            |             |            |
| **Grid Occurrences**                        |    ✓     |      ✓      |     ✓      |         ✓          |   ✓   |     ✓      |             |     ✓      |
| **Maintenance Monitoring**                  |    ✓     |      ✓      |     ✓      |         ✓          |   ✓   |            |     ✓       |     ✓      |
| **Power System Monitoring and Performance** |    ✓     |             |     ✓      |         ✓          |   ✓   |            |             |            |
| **Asset Management**                        |    ✓     |      ✓      |     ✓      |         ✓          |   ✓   |            |             |     ✓      |

---

## 3. Dimensional Model

### 3.1 Conceptual Diagram (Galaxy Schema)

Dim_Date ─┐
Dim_Time_of_Day ─┤
Dim_Power_Plant ─┤ ┌── Fact_Energy_Generation
Dim_Substation ──┼──────────┼── Fact_Energy_Transmission
Dim_Transmission_Line ─┤ ├── Fact_Power_System_Monitoring
Dim_State ────────┤ ├── Fact_Grid_Occurrence
Dim_Occurrence_Type ─┤ ├── Fact_Maintenance
Dim_Maintenance_Type ┘ ├── Fact_Asset_Status
Dim_Junk_Flags ─────────────┘


Power Plant, Substation and Transmission Line are the three "physical asset" dimensions shared across nearly every fact, forming a galaxy schema.

### 3.2 Conventions

- **Surrogate Key (SK):** sequential integer, generated during load.
- **Business Key (NK):** sourced from the Data Vault (hash_key).
- **SCD:** Slowly Changing Dimension – Type 1 (overwrite), Type 2 (new row with start/end dates). A dimension is classified as **Type 2** overall; the document lists which attributes trigger a new row (Type 2) and which are overwritten in place (Type 1).
- **Vault Source:** indicates which Data Vault table and column the data is extracted from. Names match the Data Vault Design Document exactly.
- **Degenerate Dimension (DD):** an operational identifier stored directly on the fact table (e.g., work order number).
- **Junk Dimension:** combines low‑cardinality flags/indicators into a single table to reduce fact table width.
- **Additive measure:** can be summed across all dimensions.
- **Semi-additive measure:** can be summed across some dimensions but not time.
- **Non-additive measure:** cannot be summed meaningfully under any dimension — should be averaged or recalculated.

---

## 4. Conformed Dimensions

### 4.1 Dim_Date

*Pre‑loaded for the full operational horizon. Additional enterprise attributes have been added.*

| Attribute        | Type    | Description                         | SCD | Vault Source / Rule       |
|------------------|---------|-------------------------------------|-----|----------------------------|
| sk_date          | INT PK  | Surrogate key                       | –   | Generated                  |
| full_date        | DATE    | Date in YYYY-MM-DD format           | –   | Date sequence               |
| year             | INT     |                                     | –   | Derived from full_date      |
| quarter          | INT     | 1–4                                 | –   | Derived from full_date      |
| quarter_name     | VARCHAR | e.g., "Q1 2026"                    | –   | Derived                    |
| month            | INT     | 1–12                                | –   | Derived from full_date      |
| month_name       | VARCHAR |                                     | –   | Derived from full_date      |
| week_number      | INT     | ISO week number                     | –   | Derived from full_date      |
| day              | INT     | Day of month                        | –   | Derived from full_date      |
| day_of_year      | INT     | Day number within the year          | –   | Derived from full_date      |
| day_of_week      | VARCHAR |                                     | –   | Derived from full_date      |
| is_weekend       | BOOLEAN |                                     | –   | Derived from full_date      |
| semester         | INT     | 1 or 2                               | –   | Derived from full_date      |
| holiday_flag     | BOOLEAN | National/regional holiday indicator | 1   | Holidays reference table    |
| month_start_flag | BOOLEAN | True if first day of month           | –   | Derived                    |
| month_end_flag   | BOOLEAN | True if last day of month            | –   | Derived                    |

### 4.2 Dim_Time_of_Day

*Pre‑loaded (1,440 rows). Added shift and peak/off‑peak indicators for electrical analytics.*

| Attribute        | Type    | Description                          | SCD | Vault Source / Rule |
|------------------|---------|--------------------------------------|-----|-----------------------|
| sk_time_of_day   | INT PK  | Surrogate key (0–1439)               | –   | Generated             |
| hour             | INT     | 0–23                                 | –   | Generated             |
| minute           | INT     | 0–59                                 | –   | Generated             |
| hh_mm            | VARCHAR | Display format, e.g., "14:35"        | –   | Generated             |
| period_of_day    | VARCHAR | Dawn / Morning / Afternoon / Night   | –   | Derived               |
| shift            | VARCHAR | 'Day Shift', 'Evening', 'Night'      | –   | Derived (e.g., 06‑14, 14‑22, 22‑06) |
| peak_period      | BOOLEAN | True if within peak hours (18‑21)    | –   | Derived               |
| off_peak_period  | BOOLEAN | True if within off‑peak hours        | –   | Derived               |

> Facts at minute granularity reference **both** sk_date and sk_time_of_day.

### 4.3 Dim_Power_Plant

*Type 2 dimension.*  
**Type 2 tracked attributes:** installed_capacity_mw, operator_name, status.  
**Type 1 overwrite attributes:** plant_name, plant_type, state_name (all other attributes are overwritten in place on the current row).

| Attribute              | Type     | Description                                  | Vault Source                                  |
|------------------------|----------|----------------------------------------------|------------------------------------------------|
| sk_power_plant         | INT PK   | Surrogate key                                | Generated                                      |
| hash_key_power_plant   | CHAR(64) | Business key                                 | hub_power_plant.hash_key_power_plant            |
| plant_name             | VARCHAR  | Plant name                                   | sat_power_plant_attributes.plant_name            |
| plant_type             | VARCHAR  | Hydro / Thermal / Wind / Solar / Nuclear      | sat_power_plant_attributes.plant_type            |
| installed_capacity_mw  | DECIMAL  | Nameplate capacity (Type 2)                  | sat_power_plant_attributes.installed_capacity_mw |
| commissioning_date     | DATE     | Date plant entered operation                  | sat_power_plant_attributes.commissioning_date    |
| operator_name          | VARCHAR  | Operating company (Type 2)                   | sat_power_plant_attributes.operator_name         |
| state_name             | VARCHAR  | State where the plant is located (denormalized)| link_power_plant_state → dim_state              |
| status                 | VARCHAR  | Active / Decommissioned / Under Construction (Type 2)| sat_power_plant_status.status                |
| start_date             | DATE     | Validity start (SCD2)                        | Calculated during load                           |
| end_date               | DATE     | Validity end (SCD2)                          | Calculated during load                           |
| sk_state               | INT FK   | Surrogate key for state                      | dim_state.sk_state (via link_power_plant_state)  |

### 4.4 Dim_Substation

*Type 2 dimension.*  
**Type 2 tracked attributes:** voltage_level_kv, status.  
**Type 1 overwrite attributes:** substation_name, substation_type, state_name.

| Attribute            | Type     | Description                          | Vault Source                             |
|----------------------|----------|--------------------------------------|------------------------------------------|
| sk_substation        | INT PK   | Surrogate key                        | Generated                                |
| hash_key_substation  | CHAR(64) | Business key                         | hub_substation.hash_key_substation        |
| substation_name      | VARCHAR  | Substation name                      | sat_substation_attributes.substation_name |
| voltage_level_kv     | DECIMAL  | Primary voltage level (Type 2)       | sat_substation_attributes.voltage_level_kv|
| substation_type      | VARCHAR  | Step-up / Step-down / Switching      | sat_substation_attributes.substation_type |
| state_name           | VARCHAR  | State where the substation is located| link_substation_state → dim_state        |
| status               | VARCHAR  | Active / Decommissioned / Planned (Type 2)| sat_substation_status.status            |
| start_date           | DATE     | Validity start (SCD2)                | Calculated during load                    |
| end_date             | DATE     | Validity end (SCD2)                  | Calculated during load                    |
| sk_state             | INT FK   | Surrogate key for state              | dim_state.sk_state (via link_substation_state) |

### 4.5 Dim_Transmission_Line

*Type 2 dimension.*  
**Type 2 tracked attributes:** voltage_level_kv, status.  
**Type 1 overwrite attributes:** all other descriptive attributes, including coordinates and names.

| Attribute              | Type     | Description                              | Vault Source                                 |
|------------------------|----------|------------------------------------------|----------------------------------------------|
| sk_transmission_line   | INT PK   | Surrogate key                            | Generated                                    |
| hash_key_line          | CHAR(64) | Business key                             | hub_transmission_line.hash_key_transmission_line |
| line_code              | VARCHAR  | Operational line code/name               | sat_line_attributes.line_code                |
| voltage_level_kv       | DECIMAL  | Nominal voltage (Type 2)                 | sat_line_attributes.voltage_level_kv         |
| length_km              | DECIMAL  | Line length                              | sat_line_attributes.length_km                |
| circuit_type           | VARCHAR  | AC / DC                                  | sat_line_attributes.circuit_type             |
| origin_substation_name | VARCHAR  | Origin substation (denormalized)         | link_transmission_line_substation (role ORIGIN) → dim_substation |
| destination_substation_name | VARCHAR | Destination substation (denormalized)| link_transmission_line_substation (role DESTINATION) → dim_substation |
| origin_latitude        | DECIMAL(9,6)| Latitude of origin                       | sat_line_attributes.origin_latitude          |
| origin_longitude       | DECIMAL(9,6)| Longitude of origin                      | sat_line_attributes.origin_longitude         |
| destination_latitude   | DECIMAL(9,6)| Latitude of destination                  | sat_line_attributes.destination_latitude     |
| destination_longitude  | DECIMAL(9,6)| Longitude of destination                 | sat_line_attributes.destination_longitude    |
| midpoint_latitude      | DECIMAL(9,6)| Midpoint latitude                        | sat_line_attributes.midpoint_latitude        |
| midpoint_longitude     | DECIMAL(9,6)| Midpoint longitude                       | sat_line_attributes.midpoint_longitude       |
| status                 | VARCHAR  | Active / Decommissioned / Planned (Type 2)| sat_line_status.status                       |
| start_date             | DATE     | Validity start (SCD2)                    | Calculated during load                       |
| end_date               | DATE     | Validity end (SCD2)                      | Calculated during load                       |

*Note: Dim_Transmission_Line does not include a direct state attribute because a line can span multiple states. State is derived from origin/destination substations when needed for facts.*

### 4.6 Dim_State

*(Formerly Dim_Region. Aligned with `hub_state` and `sat_state_attributes` in Data Vault.)*

| Attribute          | Type     | Description                        | Vault Source                          |
|--------------------|----------|------------------------------------|----------------------------------------|
| sk_state           | INT PK   | Surrogate key                      | Generated                              |
| hash_key_state     | CHAR(64) | Business key                       | hub_state.hash_key_state               |
| state_code         | VARCHAR(10)| State abbreviation (UF)           | hub_state.state_code                   |
| state_name         | VARCHAR(50)| Full state name                   | sat_state_attributes.state_name        |
| ons_control_area   | VARCHAR(50)| ONS operational control area      | sat_state_attributes.ons_control_area  |

### 4.7 Dim_Occurrence_Type

| Attribute              | Type    | Description                             | Vault Source                            |
|------------------------|---------|-----------------------------------------|------------------------------------------|
| sk_occurrence_type     | INT PK  | Surrogate key                          | Generated                                |
| hash_key_occurrence_type| CHAR(64)| Business key                           | hub_occurrence_type.hash_key_occurrence_type |
| occurrence_category    | VARCHAR | Outage / Equipment Failure / Alarm / Emergency | sat_occurrence_type_attributes.category |
| occurrence_subtype     | VARCHAR | Specific classification                | sat_occurrence_type_attributes.subtype   |
| severity_level         | VARCHAR | Low / Medium / High / Critical         | sat_occurrence_type_attributes.severity_level |

### 4.8 Dim_Maintenance_Type

| Attribute              | Type    | Description                          | Vault Source                          |
|------------------------|---------|--------------------------------------|----------------------------------------|
| sk_maintenance_type    | INT PK  | Surrogate key                        | Generated                              |
| hash_key_maintenance_type| CHAR(64)| Business key                        | hub_maintenance_type.hash_key_maintenance_type |
| maintenance_category   | VARCHAR | Preventive / Corrective              | sat_maintenance_type_attributes.category |
| maintenance_subtype    | VARCHAR | Inspection / Work Order / Overhaul   | sat_maintenance_type_attributes.subtype |
| priority_level         | VARCHAR | Low / Medium / High / Urgent         | sat_maintenance_type_attributes.priority_level |

### 4.9 Dim_Junk_Flags

*Junk dimension replacing individual boolean flags on fact tables. Static, pre‑loaded with 27 rows.*

| Attribute         | Type    | Description                                           | Vault Source / Rule                                                                                 |
|-------------------|---------|-------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| sk_junk_flags     | INT PK  | Surrogate key                                         | Generated (pre‑loaded)                                                                              |
| resolved_flag     | CHAR(3) | Occurrence resolved? `'Y'` / `'N'` / `'N/A'`           | `sat_occurrence_detail.resolved_flag` → `'Y'`/`'N'`; otherwise `'N/A'`                             |
| overdue_flag      | CHAR(3) | Work order overdue? `'Y'` / `'N'` / `'N/A'`            | `sat_work_order_detail.overdue_flag` → `'Y'`/`'N'`; otherwise `'N/A'`                              |
| in_operation_flag | CHAR(3) | Asset in service? `'Y'` / `'N'` / `'N/A'`              | `sat_*_daily_snapshot.in_operation_flag` → `'Y'`/`'N'`; otherwise `'N/A'`                          |

---

## 5. Fact Tables

### 5.1 Fact_Energy_Generation

| Attribute              | Type    | Description                       | Vault Source / Rule                          |
|------------------------|---------|-----------------------------------|----------------------------------------------|
| sk_date                | INT FK  | Measurement date                  | dim_date.sk_date                             |
| sk_time_of_day         | INT FK  | Measurement minute                | dim_time_of_day.sk_time_of_day               |
| sk_power_plant         | INT FK  | Generating plant                  | dim_power_plant.sk_power_plant (valid at reading date) |
| sk_state               | INT FK  | State where the plant is located  | dim_state.sk_state (via dim_power_plant)      |
| generation_output_mw   | DECIMAL | Active power generated (instantaneous) | sat_gen_reading.generation_output_mw       |
| available_capacity_mw  | DECIMAL | Capacity available at that minute | sat_gen_reading.available_capacity_mw         |
| capacity_factor_pct    | DECIMAL | output / installed_capacity       | Calculated                                    |

**Granularity:** One row per power plant per minute.
**Measure classification:**
- Semi-additive: `generation_output_mw`, `available_capacity_mw`
- Non-additive: `capacity_factor_pct`
- To obtain additive energy, compute `SUM(generation_output_mw) / 60` to get MWh.

### 5.2 Fact_Energy_Transmission

| Attribute              | Type    | Description                        | Vault Source / Rule                       |
|------------------------|---------|------------------------------------|-------------------------------------------|
| sk_date                | INT FK  | Measurement date                   | dim_date.sk_date                          |
| sk_time_of_day         | INT FK  | Measurement minute                 | dim_time_of_day.sk_time_of_day            |
| sk_transmission_line   | INT FK  | Transmission line                  | dim_transmission_line.sk_transmission_line (valid at reading date) |
| sk_state               | INT FK  | State (derived from origin substation or dominant state) | dim_state.sk_state (via ETL) |
| power_flow_mw          | DECIMAL | Active power flow (instantaneous)  | sat_line_measurement.power_flow_mw        |
| line_loading_pct       | DECIMAL | flow / thermal_limit               | Calculated                                 |
| losses_mw              | DECIMAL | Transmission losses (instantaneous)| sat_line_measurement.losses_mw             |

**Granularity:** One row per transmission line per minute.
**Measure classification:**
- Semi-additive: `power_flow_mw`, `losses_mw`
- Non-additive: `line_loading_pct`

### 5.3 Fact_Power_System_Monitoring

| Attribute              | Type    | Description                        | Vault Source / Rule                       |
|------------------------|---------|------------------------------------|-------------------------------------------|
| sk_date                | INT FK  | Measurement date                   | dim_date.sk_date                          |
| sk_time_of_day         | INT FK  | Measurement minute                 | dim_time_of_day.sk_time_of_day            |
| sk_substation          | INT FK  | Monitoring point (substation) – nullable | dim_substation.sk_substation           |
| sk_transmission_line   | INT FK  | Monitoring point (line) – nullable | dim_transmission_line.sk_transmission_line |
| sk_state               | INT FK  | State of the monitoring point      | dim_state.sk_state (derived from asset)    |
| frequency_hz           | DECIMAL | System frequency                   | sat_substation_measurement.frequency_hz / sat_line_measurement.frequency_hz |
| voltage_kv             | DECIMAL | Measured voltage                   | sat_substation_measurement.voltage_kv / sat_line_measurement.voltage_kv |
| reliability_index      | DECIMAL | Composite reliability score        | sat_substation_measurement.reliability_index (only for substations) |
| system_load_mw         | DECIMAL | Instantaneous system load          | sat_substation_measurement.system_load_mw (only for substations) |

**Granularity:** One row per measurement point per minute.  
**Constraint:** Exactly one of `sk_substation` or `sk_transmission_line` must be non-null.

**Measure classification:**
- Semi-additive: `system_load_mw`
- Non-additive: `frequency_hz`, `voltage_kv`, `reliability_index`

### 5.4 Fact_Grid_Occurrence

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|------------------------|---------|--------------------------------------|----------------------------------------------|
| occurrence_id          | VARCHAR | Degenerate dimension – ticket number | hub_occurrence.ticket_number                 |
| sk_date                | INT FK  | Event start date                     | dim_date.sk_date                             |
| sk_time_of_day         | INT FK  | Event start time                     | dim_time_of_day.sk_time_of_day               |
| sk_power_plant         | INT FK  | Affected plant (nullable)            | link_occurrence_power_plant → dim_power_plant |
| sk_substation          | INT FK  | Affected substation (nullable)       | link_occurrence_substation → dim_substation  |
| sk_transmission_line   | INT FK  | Affected line (nullable)             | link_occurrence_transmission_line → dim_transmission_line |
| sk_state               | INT FK  | State of the affected asset          | dim_state.sk_state (derived from asset)      |
| sk_occurrence_type     | INT FK  | Type/category/severity               | dim_occurrence_type.sk_occurrence_type        |
| sk_junk_flags          | INT FK  | Junk dimension for flags             | dim_junk_flags.sk_junk_flags (resolved_flag = 'Y'/'N', others 'N/A') |
| duration_minutes       | DECIMAL | Time to resolution                   | sat_occurrence_detail.duration_minutes       |
| affected_load_mw       | DECIMAL | Load impacted                        | sat_occurrence_detail.affected_load_mw        |
| customers_affected     | INT     | Customers impacted                   | sat_occurrence_detail.customers_affected      |

**Granularity:** One row per occurrence event per affected asset.  
**Measure classification:**
- Additive: `duration_minutes`, `affected_load_mw`, `customers_affected`

### 5.5 Fact_Maintenance

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|------------------------|---------|--------------------------------------|----------------------------------------------|
| work_order_number      | VARCHAR | Degenerate dimension – order number  | hub_work_order.order_number                  |
| sk_date                | INT FK  | Scheduled/executed date              | dim_date.sk_date                             |
| sk_power_plant         | INT FK  | Asset under maintenance (nullable)   | link_work_order_power_plant → dim_power_plant |
| sk_substation          | INT FK  | Asset under maintenance (nullable)   | link_work_order_substation → dim_substation  |
| sk_transmission_line   | INT FK  | Asset under maintenance (nullable)   | link_work_order_transmission_line → dim_transmission_line |
| sk_state               | INT FK  | State of the asset                   | dim_state.sk_state (derived from asset)      |
| sk_maintenance_type    | INT FK  | Category/subtype/priority            | dim_maintenance_type.sk_maintenance_type      |
| sk_junk_flags          | INT FK  | Junk dimension for flags             | dim_junk_flags.sk_junk_flags (overdue_flag = 'Y'/'N', others 'N/A') |
| planned_duration_hours | DECIMAL | Planned work duration                | sat_work_order_detail.planned_duration_hours |
| actual_duration_hours  | DECIMAL | Actual work duration                 | sat_work_order_detail.actual_duration_hours   |
| cost                   | DECIMAL | Maintenance cost                     | sat_work_order_detail.cost                   |
| asset_availability_pct | DECIMAL | Asset availability during the period | sat_work_order_detail.asset_availability_pct   |

**Granularity:** One row per maintenance activity per asset.  
**Measure classification:**
- Additive: `planned_duration_hours`, `actual_duration_hours`, `cost`
- Semi-additive: `asset_availability_pct`

### 5.6 Fact_Asset_Status

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|------------------------|---------|--------------------------------------|----------------------------------------------|
| sk_date                | INT FK  | Snapshot date                        | dim_date.sk_date                             |
| sk_power_plant         | INT FK  | Asset (nullable)                     | dim_power_plant.sk_power_plant (valid at snapshot) |
| sk_substation          | INT FK  | Asset (nullable)                     | dim_substation.sk_substation                |
| sk_transmission_line   | INT FK  | Asset (nullable)                     | dim_transmission_line.sk_transmission_line   |
| sk_state               | INT FK  | State of the asset                   | dim_state.sk_state (derived from asset)      |
| sk_junk_flags          | INT FK  | Junk dimension for flags             | dim_junk_flags.sk_junk_flags (in_operation_flag = 'Y'/'N', others 'N/A') |
| availability_pct       | DECIMAL | % of the day the asset was available | sat_*_daily_snapshot.availability_pct        |
| asset_age_years        | DECIMAL | Age since commissioning              | Calculated in ETL (snapshot_date − commissioning_date from dimension) |

**Granularity:** One row per physical asset per day. Exactly one asset FK is non-null.  
**Measure classification:**
- Semi-additive: `availability_pct`
- Non-additive: `asset_age_years`

---

## 6. Glossary and Metadata

| Term                  | Definition                                                                                  | Owner      |
|-----------------------|----------------------------------------------------------------------------------------------|------------|
| ONS                   | Operador Nacional do Sistema Elétrico – Brazilian ISO                                        | Operations |
| Active Power (MW)     | Instantaneous electric power flow                                                            | Engineering|
| Energy (MWh)          | Integrated power over time, computed as AVG(MW) * hours                                      | Analytics  |
| Capacity Factor       | Ratio of actual generation to maximum possible generation (nameplate capacity × time)        | Engineering|
| SCD2                  | Slowly Changing Dimension Type 2 – preserves history by creating a new row                   | Data       |
| Degenerate Dimension  | Transactional identifier stored directly on the fact table                                   | Data       |
| Junk Dimension        | Dimension combining low‑cardinality flags/indicators to simplify fact tables                 | Data       |
| Galaxy Schema         | A dimensional model with multiple fact tables sharing conformed dimensions                   | Data       |

---

## 7. Performance and Security

- **Indexes:** B-tree on all foreign keys in fact tables; bitmap indexes on frequently filtered dimension columns (e.g., `state_name`, `status`).
- **Partitioning:** partition fact tables by `sk_date` (year-month).
- **Aggregations:** consider daily/monthly aggregates for common dashboards.
- **Row-Level Security (RLS):** optional filters on `dim_state` to restrict data by operational area.

---

## 8. Revisions

| Version | Date       | Changes                                                                                                                      | Author           |
|---------|------------|------------------------------------------------------------------------------------------------------------------------------|------------------|
| 1.0     | 07/21/2026 | Initial creation                                                                                                              | Guilherme Roriz  |
| 1.1     | 07/21/2026 | Refined measure classification, corrected fact granularity notes                                                             | Guilherme Roriz  |
| 1.2     | 07/21/2026 | Corrected SCD2 join logic, added glossary, partitioning                                                                      | Guilherme Roriz  |
| 1.3     | 07/23/2026 | Replaced Dim_Region with Dim_State, added geographic coordinates                                                             | Guilherme Roriz  |
| 1.4     | 07/23/2026 | Review pass, aligned Vault Source names, fixed column names, degenerate dimensions from business keys                        | Guilherme Roriz  |
| 1.5     | 07/24/2026 | Introduced Dim_Junk_Flags, adjusted affected facts, added Junk Flags to bus matrix                                           | Guilherme Roriz  |
| 1.6     | 07/24/2026 | Overhauled SCD documentation (dimension‑level Type 2 with attribute classification); enhanced Dim_Date and Dim_Time_of_Day with enterprise attributes; renamed `grid_operator_area` to `ons_control_area`; removed any remaining `region` references; added architecture overview diagram | Guilherme Roriz  |
