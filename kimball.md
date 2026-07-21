
Power Plant, Substation and Transmission Line act as the three "physical asset" dimensions and are shared across nearly every fact, which is what makes this a galaxy rather than a single star schema.

### 3.2 Conventions

- **Surrogate Key (SK):** sequential integer, generated during load.
- **Business Key (NK):** sourced from the Data Vault (hash_key).
- **SCD:** Slowly Changing Dimension – Type 1 (overwrite), Type 2 (new row with start/end dates), Type 3 (separate previous/current column).
- **Vault Source:** indicates which Data Vault table the data is extracted from.
- **Degenerate Dimension (DD):** an operational identifier (e.g., work order number) stored directly on the fact table with no corresponding dimension table.
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
|------------------------|----------|-------------------------------------------------|-----|-------------------------------------------------|
| sk_power_plant         | INT PK   | Surrogate key                                  | –   | Generated                                         |
| hash_key_power_plant   | CHAR(32) | Business key                                   | –   | hub_power_plant.hash_key_power_plant              |
| plant_name             | VARCHAR  | Plant name                                     | 1   | sat_power_plant_attributes.name                   |
| plant_type             | VARCHAR  | Hydro / Thermal / Wind / Solar / Nuclear         | 1   | sat_power_plant_attributes.type                    |
| installed_capacity_mw  | DECIMAL  | Nameplate capacity                             | 2   | sat_power_plant_attributes.installed_capacity      |
| commissioning_date     | DATE     | Date plant entered operation                   | –   | sat_power_plant_attributes.commissioning_date       |
| operator_name          | VARCHAR  | Operating company                              | 2   | sat_power_plant_attributes.operator                 |
| region_name            | VARCHAR  | Region the plant belongs to (denormalized)     | 1   | link_power_plant_region → dim_region                |
| status                 | VARCHAR  | Active / Decommissioned / Under Construction   | 2   | sat_power_plant_status.status                       |
| start_date             | DATE     | Validity start (SCD2)                          | 2   | Calculated during load                              |
| end_date               | DATE     | Validity end (SCD2)                            | 2   | Calculated during load                              |

### 4.4 Dim_Substation

| Attribute            | Type     | Description                          | SCD | Vault Source                             |
|----------------------|----------|-----------------------------------------|-----|---------------------------------------------|
| sk_substation        | INT PK   | Surrogate key                          | –   | Generated                                     |
| hash_key_substation  | CHAR(32) | Business key                           | –   | hub_substation.hash_key_substation            |
| substation_name      | VARCHAR  | Substation name                        | 1   | sat_substation_attributes.name                 |
| voltage_level_kv     | DECIMAL  | Primary voltage level                  | 2   | sat_substation_attributes.voltage_level        |
| substation_type      | VARCHAR  | Step-up / Step-down / Switching        | 1   | sat_substation_attributes.type                 |
| region_name          | VARCHAR  | Region (denormalized)                  | 1   | link_substation_region → dim_region            |
| status               | VARCHAR  | Active / Decommissioned / Planned      | 2   | sat_substation_status.status                    |
| start_date           | DATE     | Validity start (SCD2)                  | 2   | Calculated during load                          |
| end_date             | DATE     | Validity end (SCD2)                    | 2   | Calculated during load                          |

### 4.5 Dim_Transmission_Line

| Attribute              | Type     | Description                              | SCD | Vault Source                                 |
|-------------------------|----------|--------------------------------------------|-----|--------------------------------------------------|
| sk_transmission_line    | INT PK   | Surrogate key                            | –   | Generated                                         |
| hash_key_line           | CHAR(32) | Business key                             | –   | hub_transmission_line.hash_key_line               |
| line_code               | VARCHAR  | Operational line code/name               | 1   | sat_line_attributes.code                           |
| voltage_level_kv        | DECIMAL  | Nominal voltage                          | 2   | sat_line_attributes.voltage_level                  |
| length_km               | DECIMAL  | Line length                              | 1   | sat_line_attributes.length_km                      |
| circuit_type            | VARCHAR  | AC / DC                                  | 1   | sat_line_attributes.circuit_type                   |
| origin_substation_name  | VARCHAR  | Origin substation (denormalized)         | 1   | link_line_substation → dim_substation               |
| destination_substation_name | VARCHAR | Destination substation (denormalized)| 1   | link_line_substation → dim_substation               |
| region_name             | VARCHAR  | Region (denormalized)                    | 1   | link_line_region → dim_region                       |
| status                  | VARCHAR  | Active / Decommissioned / Planned        | 2   | sat_line_status.status                              |
| start_date              | DATE     | Validity start (SCD2)                    | 2   | Calculated during load                              |
| end_date                | DATE     | Validity end (SCD2)                      | 2   | Calculated during load                              |

### 4.6 Dim_Region

| Attribute        | Type     | Description                        | SCD | Vault Source                          |
|-------------------|----------|---------------------------------------|-----|------------------------------------------|
| sk_region         | INT PK   | Surrogate key                        | –   | Generated                                 |
| hash_key_region   | CHAR(32) | Business key                         | –   | hub_region.hash_key_region                |
| region_name       | VARCHAR  | Region/subsystem name                | 1   | sat_region_attributes.name                 |
| state_province    | VARCHAR  | State or province                    | 1   | sat_region_attributes.state                 |
| grid_operator_area| VARCHAR  | ONS operational control area         | 1   | sat_region_attributes.control_area          |

### 4.7 Dim_Occurrence_Type

| Attribute              | Type    | Description                             | SCD | Vault Source                            |
|-------------------------|---------|--------------------------------------------|-----|--------------------------------------------|
| sk_occurrence_type      | INT PK  | Surrogate key                             | –   | Generated                                   |
| occurrence_category     | VARCHAR | Outage / Equipment Failure / Alarm / Emergency | 1 | sat_occurrence_type.category               |
| occurrence_subtype      | VARCHAR | Specific classification                   | 1   | sat_occurrence_type.subtype                 |
| severity_level          | VARCHAR | Low / Medium / High / Critical            | 1   | sat_occurrence_type.severity                |

### 4.8 Dim_Maintenance_Type

| Attribute              | Type    | Description                          | SCD | Vault Source                          |
|-------------------------|---------|-----------------------------------------|-----|------------------------------------------|
| sk_maintenance_type     | INT PK  | Surrogate key                         | –   | Generated                                 |
| maintenance_category    | VARCHAR | Preventive / Corrective               | 1   | sat_maintenance_type.category             |
| maintenance_subtype     | VARCHAR | Inspection / Work Order / Overhaul    | 1   | sat_maintenance_type.subtype               |
| priority_level          | VARCHAR | Low / Medium / High / Urgent          | 1   | sat_maintenance_type.priority               |

---

## 5. Fact Tables

### 5.1 Fact_Energy_Generation

| Attribute              | Type    | Description                       | Vault Source / Rule                          |
|-------------------------|---------|--------------------------------------|-------------------------------------------------|
| sk_date                | INT FK  | Measurement date                  | dim_date.sk_date                                 |
| sk_time_of_day         | INT FK  | Measurement minute                | dim_time_of_day.sk_time_of_day                    |
| sk_power_plant         | INT FK  | Generating plant                  | dim_power_plant.sk_power_plant (valid version at reading date) |
| sk_region              | INT FK  | Region                            | dim_region.sk_region                              |
| generation_output_mw   | DECIMAL | Active power generated (instantaneous) | sat_generation_reading.output_mw            |
| available_capacity_mw  | DECIMAL | Capacity available at that minute | sat_generation_reading.available_capacity           |
| capacity_factor_pct    | DECIMAL | output / installed_capacity (from the plant version valid at reading date) | Calculated |

**Granularity:** One row per power plant per minute.
**Measure classification:**
- Semi-additive (cannot be summed over time): `generation_output_mw`, `available_capacity_mw`
- Non-additive: `capacity_factor_pct`
- To obtain additive energy, compute `SUM(generation_output_mw) / 60` to get megawatt-hours (MWh).

### 5.2 Fact_Energy_Transmission

| Attribute              | Type    | Description                        | Vault Source / Rule                       |
|-------------------------|---------|----------------------------------------|-----------------------------------------------|
| sk_date                | INT FK  | Measurement date                    | dim_date.sk_date                                |
| sk_time_of_day         | INT FK  | Measurement minute                  | dim_time_of_day.sk_time_of_day                   |
| sk_transmission_line   | INT FK  | Transmission line                   | dim_transmission_line.sk_transmission_line (valid version at reading date) |
| sk_region              | INT FK  | Region                              | dim_region.sk_region                              |
| power_flow_mw          | DECIMAL | Active power flow (instantaneous)   | sat_transmission_reading.power_flow_mw             |
| line_loading_pct       | DECIMAL | flow / thermal_limit                | Calculated (using line characteristics valid at reading date) |
| losses_mw              | DECIMAL | Transmission losses (instantaneous) | sat_transmission_reading.losses_mw                  |

**Granularity:** One row per transmission line per minute.
**Measure classification:**
- Semi-additive: `power_flow_mw`, `losses_mw`
- Non-additive: `line_loading_pct`

### 5.3 Fact_Power_System_Monitoring

| Attribute              | Type    | Description                        | Vault Source / Rule                       |
|-------------------------|---------|----------------------------------------|-----------------------------------------------|
| sk_date                | INT FK  | Measurement date                    | dim_date.sk_date                                |
| sk_time_of_day         | INT FK  | Measurement minute                  | dim_time_of_day.sk_time_of_day                   |
| sk_substation          | INT FK  | Monitoring point (substation) – used when measurement point is a substation | dim_substation.sk_substation (nullable)          |
| sk_transmission_line   | INT FK  | Monitoring point (line) – used when measurement point is on a line | dim_transmission_line.sk_transmission_line (nullable) |
| sk_region              | INT FK  | Region                              | dim_region.sk_region                              |
| frequency_hz           | DECIMAL | System frequency (non-additive)     | sat_system_measurement.frequency                   |
| voltage_kv             | DECIMAL | Measured voltage (non-additive)     | sat_system_measurement.voltage                     |
| reliability_index      | DECIMAL | Composite reliability score (non-additive) | sat_system_measurement.reliability_index   |
| system_load_mw         | DECIMAL | Instantaneous system load (semi-additive) | sat_system_measurement.load_mw            |

**Granularity:** One row per measurement point per minute.  
**Constraint:** Exactly one of `sk_substation` or `sk_transmission_line` must be non-null; the other must be null. This enforces that a measurement point belongs to exactly one asset type.

**Measure classification:**
- Semi-additive: `system_load_mw`
- Non-additive: `frequency_hz`, `voltage_kv`, `reliability_index`

### 5.4 Fact_Grid_Occurrence

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|-------------------------|---------|------------------------------------------|--------------------------------------------------|
| occurrence_id          | VARCHAR | Degenerate dimension – event/ticket ID | hub_occurrence.hash_key_occurrence (business ID)  |
| sk_date                | INT FK  | Event start date                       | dim_date.sk_date                                    |
| sk_time_of_day         | INT FK  | Event start time                       | dim_time_of_day.sk_time_of_day                       |
| sk_power_plant         | INT FK  | Affected plant (nullable)              | link_occurrence_asset → dim_power_plant (valid version at event date) |
| sk_substation          | INT FK  | Affected substation (nullable)         | link_occurrence_asset → dim_substation                |
| sk_transmission_line   | INT FK  | Affected line (nullable)               | link_occurrence_asset → dim_transmission_line          |
| sk_region              | INT FK  | Region                                 | dim_region.sk_region                                  |
| sk_occurrence_type     | INT FK  | Type/category/severity                 | dim_occurrence_type.sk_occurrence_type                 |
| duration_minutes       | DECIMAL | Time to resolution                     | sat_occurrence_detail.duration_minutes                  |
| affected_load_mw       | DECIMAL | Load impacted                          | sat_occurrence_detail.affected_load_mw                   |
| customers_affected     | INT     | Customers impacted                     | sat_occurrence_detail.customers_affected                 |
| resolved_flag          | BOOLEAN | Whether the occurrence is closed       | sat_occurrence_detail.resolved_flag                       |

**Granularity:** One row per occurrence event per affected asset. If an occurrence affects multiple assets, it is split into multiple rows, each with a single non-null asset FK.  
**Measure classification:**
- Additive: `duration_minutes`, `affected_load_mw`, `customers_affected`
- Non-additive: `resolved_flag`

### 5.5 Fact_Maintenance

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|-------------------------|---------|------------------------------------------|--------------------------------------------------|
| work_order_number      | VARCHAR | Degenerate dimension – work order ID    | hub_work_order.hash_key_work_order (business ID)   |
| sk_date                | INT FK  | Scheduled/executed date                | dim_date.sk_date                                    |
| sk_power_plant         | INT FK  | Asset under maintenance (nullable)     | link_maintenance_asset → dim_power_plant (valid version at date) |
| sk_substation          | INT FK  | Asset under maintenance (nullable)     | link_maintenance_asset → dim_substation               |
| sk_transmission_line   | INT FK  | Asset under maintenance (nullable)     | link_maintenance_asset → dim_transmission_line         |
| sk_region              | INT FK  | Region                                 | dim_region.sk_region                                  |
| sk_maintenance_type    | INT FK  | Category/subtype/priority              | dim_maintenance_type.sk_maintenance_type                |
| planned_duration_hours | DECIMAL | Planned work duration                  | sat_maintenance_detail.planned_duration_hours            |
| actual_duration_hours  | DECIMAL | Actual work duration                   | sat_maintenance_detail.actual_duration_hours              |
| cost                   | DECIMAL | Maintenance cost                       | sat_maintenance_detail.cost                              |
| overdue_flag           | BOOLEAN | Activity past scheduled date           | sat_maintenance_detail.overdue_flag                       |
| asset_availability_pct | DECIMAL | Asset availability during the period   | sat_maintenance_detail.availability_pct                    |

**Granularity:** One row per maintenance activity per asset. If a single work order covers multiple assets, it generates multiple rows (one per asset).  
**Measure classification:**
- Additive: `planned_duration_hours`, `actual_duration_hours`, `cost`
- Semi-additive: `asset_availability_pct`
- Non-additive: `overdue_flag`

### 5.6 Fact_Asset_Status

*Periodic snapshot fact that complements the master data in the asset dimensions.*

| Attribute              | Type    | Description                          | Vault Source / Rule                          |
|-------------------------|---------|------------------------------------------|--------------------------------------------------|
| sk_date                | INT FK  | Snapshot date                          | dim_date.sk_date                                    |
| sk_power_plant         | INT FK  | Asset (nullable)                       | dim_power_plant.sk_power_plant (valid version at snapshot date) |
| sk_substation          | INT FK  | Asset (nullable)                       | dim_substation.sk_substation (valid version)        |
| sk_transmission_line   | INT FK  | Asset (nullable)                       | dim_transmission_line.sk_transmission_line (valid version) |
| sk_region              | INT FK  | Region                                 | dim_region.sk_region                                  |
| availability_pct       | DECIMAL | % of the day the asset was available   | sat_asset_status.availability_pct                        |
| in_operation_flag      | BOOLEAN | Whether the asset was in service       | sat_asset_status.in_operation_flag                        |
| asset_age_years        | DECIMAL | Age since commissioning                | Calculated (snapshot_date − commissioning_date from the valid dimension row) |

**Granularity:** One row per physical asset per day. Exactly one of the asset FKs is non-null.  
**Measure classification:**
- Semi-additive: `availability_pct`
- Non-additive: `in_operation_flag`, `asset_age_years`

---

## 6. ETL Mapping (Data Vault → Galaxy)

### 6.1 Dimension Loading

*Example for Dim_Power_Plant (SCD2 on operator_name and status).*

```sql
-- Step 1: Identify new plants
INSERT INTO dim_power_plant (hash_key_power_plant, plant_name, plant_type,
    installed_capacity_mw, commissioning_date, operator_name, region_name,
    status, start_date, end_date)
SELECT h.hash_key_power_plant, s.name, s.type, s.installed_capacity,
    s.commissioning_date, s.operator, r.region_name, st.status,
    CURRENT_DATE, NULL
FROM hub_power_plant h
JOIN sat_power_plant_attributes s ON s.hash_key_power_plant = h.hash_key_power_plant
JOIN sat_power_plant_status st ON st.hash_key_power_plant = h.hash_key_power_plant
JOIN link_power_plant_region lr ON lr.hash_key_power_plant = h.hash_key_power_plant
JOIN dim_region r ON r.hash_key_region = lr.hash_key_region
WHERE h.hash_key_power_plant NOT IN (SELECT hash_key_power_plant FROM dim_power_plant);

-- Step 2: Close old versions where SCD2 attributes changed
UPDATE dim_power_plant
SET end_date = CURRENT_DATE - 1
WHERE end_date IS NULL
  AND (operator_name, status) <>
      (SELECT s.operator, st.status
       FROM sat_power_plant_attributes s
       JOIN sat_power_plant_status st USING (hash_key_power_plant)
       WHERE s.hash_key_power_plant = dim_power_plant.hash_key_power_plant);

-- Step 3: Insert new versions
INSERT INTO dim_power_plant (hash_key_power_plant, plant_name, plant_type,
    installed_capacity_mw, commissioning_date, operator_name, region_name,
    status, start_date, end_date)
SELECT h.hash_key_power_plant, s.name, s.type, s.installed_capacity,
    s.commissioning_date, s.operator, r.region_name, st.status,
    CURRENT_DATE, NULL
FROM hub_power_plant h
JOIN sat_power_plant_attributes s ON s.hash_key_power_plant = h.hash_key_power_plant
JOIN sat_power_plant_status st ON st.hash_key_power_plant = h.hash_key_power_plant
JOIN link_power_plant_region lr ON lr.hash_key_power_plant = h.hash_key_power_plant
JOIN dim_region r ON r.hash_key_region = lr.hash_key_region
WHERE (h.hash_key_power_plant, s.operator, st.status) NOT IN (
    SELECT hash_key_power_plant, operator_name, status
    FROM dim_power_plant
    WHERE end_date IS NULL
);