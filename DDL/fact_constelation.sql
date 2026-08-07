-- ============================================================
-- ONS Enterprise Data Platform – Galaxy Schema DDL
-- Schema: galaxy (Star Schema / Kimball)
-- Version: 1.8 (ETL upsert keys and percentage precision)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS galaxy;
SET search_path TO galaxy;

-- ============================================================
-- 4. Conformed Dimensions
-- ============================================================

-- 4.1 Dim_Date
CREATE TABLE dim_date (
    sk_date          INT PRIMARY KEY,
    full_date        DATE NOT NULL UNIQUE,
    year             INT NOT NULL,
    quarter          INT NOT NULL,
    quarter_name     VARCHAR(10),
    month            INT NOT NULL,
    month_name       VARCHAR(15),
    week_number      INT,
    day              INT NOT NULL,
    day_of_year      INT,
    day_of_week      VARCHAR(15),
    is_weekend       BOOLEAN NOT NULL,
    semester         INT,
    holiday_flag     BOOLEAN NOT NULL DEFAULT FALSE,
    month_start_flag BOOLEAN NOT NULL DEFAULT FALSE,
    month_end_flag   BOOLEAN NOT NULL DEFAULT FALSE
);

-- 4.2 Dim_Time_of_Day
CREATE TABLE dim_time_of_day (
    sk_time_of_day  INT PRIMARY KEY,
    hour            INT NOT NULL CHECK (hour BETWEEN 0 AND 23),
    minute          INT NOT NULL CHECK (minute BETWEEN 0 AND 59),
    hh_mm           VARCHAR(5),
    period_of_day   VARCHAR(20),
    shift           VARCHAR(20),
    peak_period     BOOLEAN NOT NULL DEFAULT FALSE,
    off_peak_period BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (hour, minute)
);

-- 4.6 Dim_State
CREATE TABLE dim_state (
    sk_state        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hash_key_state  CHAR(64) NOT NULL,
    state_code      VARCHAR(10) NOT NULL,
    state_name      VARCHAR(50) NOT NULL,
    ons_control_area VARCHAR(50)
);

-- 4.3 Dim_Power_Plant (Type 2)
CREATE TABLE dim_power_plant (
    sk_power_plant        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hash_key_power_plant  CHAR(64) NOT NULL,
    plant_name            VARCHAR(100),
    plant_type            VARCHAR(50),
    installed_capacity_mw DECIMAL(10,2),
    commissioning_date    DATE,
    operator_name         VARCHAR(100),
    state_name            VARCHAR(50),
    status                VARCHAR(20),
    start_date            DATE NOT NULL,
    end_date              DATE,
    sk_state              INT REFERENCES dim_state(sk_state)
);

-- 4.4 Dim_Substation (Type 2)
CREATE TABLE dim_substation (
    sk_substation        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hash_key_substation  CHAR(64) NOT NULL,
    substation_name      VARCHAR(100),
    voltage_level_kv     DECIMAL(6,1),
    substation_type      VARCHAR(30),
    state_name           VARCHAR(50),
    status               VARCHAR(20),
    start_date           DATE NOT NULL,
    end_date             DATE,
    sk_state             INT REFERENCES dim_state(sk_state)
);

-- 4.5 Dim_Transmission_Line (Type 2) – renamed to hash_key_transmission_line
CREATE TABLE dim_transmission_line (
    sk_transmission_line       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hash_key_transmission_line CHAR(64) NOT NULL,
    line_code                  VARCHAR(20),
    voltage_level_kv           DECIMAL(6,1),
    length_km                  DECIMAL(8,2),
    circuit_type               VARCHAR(10),
    origin_substation_name      VARCHAR(100),
    destination_substation_name VARCHAR(100),
    origin_latitude            DECIMAL(9,6),
    origin_longitude           DECIMAL(9,6),
    destination_latitude       DECIMAL(9,6),
    destination_longitude      DECIMAL(9,6),
    midpoint_latitude          DECIMAL(9,6),
    midpoint_longitude         DECIMAL(9,6),
    status                     VARCHAR(20),
    start_date                 DATE NOT NULL,
    end_date                   DATE
);

-- 4.7 Dim_Occurrence_Type
CREATE TABLE dim_occurrence_type (
    sk_occurrence_type       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hash_key_occurrence_type CHAR(64) NOT NULL,
    occurrence_category      VARCHAR(30),
    occurrence_subtype       VARCHAR(50),
    severity_level           VARCHAR(10)
);

-- 4.8 Dim_Maintenance_Type
CREATE TABLE dim_maintenance_type (
    sk_maintenance_type       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hash_key_maintenance_type CHAR(64) NOT NULL,
    maintenance_category      VARCHAR(20),
    maintenance_subtype       VARCHAR(50),
    priority_level            VARCHAR(10)
);

-- 4.9 Dim_Junk_Flags (pre-loaded with all 27 combinations)
CREATE TABLE dim_junk_flags (
    sk_junk_flags     INT PRIMARY KEY,
    resolved_flag     CHAR(3) NOT NULL CHECK (resolved_flag IN ('Y','N','N/A')),
    overdue_flag      CHAR(3) NOT NULL CHECK (overdue_flag IN ('Y','N','N/A')),
    in_operation_flag CHAR(3) NOT NULL CHECK (in_operation_flag IN ('Y','N','N/A'))
);

INSERT INTO dim_junk_flags (sk_junk_flags, resolved_flag, overdue_flag, in_operation_flag)
SELECT
    (ROW_NUMBER() OVER ()) AS sk_junk_flags,
    r.flag AS resolved_flag,
    o.flag AS overdue_flag,
    i.flag AS in_operation_flag
FROM
    (VALUES ('Y'),('N'),('N/A')) AS r(flag)
    CROSS JOIN (VALUES ('Y'),('N'),('N/A')) AS o(flag)
    CROSS JOIN (VALUES ('Y'),('N'),('N/A')) AS i(flag)
ON CONFLICT (sk_junk_flags) DO NOTHING;

-- ============================================================
-- 5. Fact Tables
-- ============================================================

-- 5.1 Fact_Energy_Generation
CREATE TABLE fact_energy_generation (
    sk_date              INT NOT NULL REFERENCES dim_date(sk_date),
    sk_time_of_day       INT NOT NULL REFERENCES dim_time_of_day(sk_time_of_day),
    sk_power_plant       INT NOT NULL REFERENCES dim_power_plant(sk_power_plant),
    sk_state             INT REFERENCES dim_state(sk_state),
    generation_output_mw DECIMAL(10,2) NOT NULL,
    available_capacity_mw DECIMAL(10,2) NOT NULL,
    capacity_factor_pct  DECIMAL(7,4),
    PRIMARY KEY (sk_date, sk_time_of_day, sk_power_plant)
);

-- 5.2 Fact_Energy_Transmission
CREATE TABLE fact_energy_transmission (
    sk_date              INT NOT NULL REFERENCES dim_date(sk_date),
    sk_time_of_day       INT NOT NULL REFERENCES dim_time_of_day(sk_time_of_day),
    sk_transmission_line INT NOT NULL REFERENCES dim_transmission_line(sk_transmission_line),
    sk_state             INT REFERENCES dim_state(sk_state),
    power_flow_mw        DECIMAL(10,2),
    line_loading_pct     DECIMAL(7,4),
    losses_mw            DECIMAL(10,2),
    PRIMARY KEY (sk_date, sk_time_of_day, sk_transmission_line)
);

-- 5.3 Fact_Power_System_Monitoring (surrogate PK + unique grain index)
CREATE TABLE fact_power_system_monitoring (
    sk_monitoring_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sk_date              INT NOT NULL REFERENCES dim_date(sk_date),
    sk_time_of_day       INT NOT NULL REFERENCES dim_time_of_day(sk_time_of_day),
    sk_substation        INT REFERENCES dim_substation(sk_substation),
    sk_transmission_line INT REFERENCES dim_transmission_line(sk_transmission_line),
    sk_state             INT REFERENCES dim_state(sk_state),
    frequency_hz         DECIMAL(6,2),
    voltage_kv           DECIMAL(6,1),
    reliability_index    DECIMAL(6,4),
    system_load_mw       DECIMAL(10,2),
    CONSTRAINT chk_one_asset CHECK (
        (sk_substation IS NOT NULL AND sk_transmission_line IS NULL) OR
        (sk_substation IS NULL AND sk_transmission_line IS NOT NULL)
    )
);

-- Unique grain: one reading per point per minute
CREATE UNIQUE INDEX uq_fmon_grain 
    ON fact_power_system_monitoring (
        sk_date, 
        sk_time_of_day, 
        COALESCE(sk_substation, -1), 
        COALESCE(sk_transmission_line, -1)
    );

-- 5.4 Fact_Grid_Occurrence (surrogate PK + unique grain index)
CREATE TABLE fact_grid_occurrence (
    sk_occurrence_fact   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurrence_id        VARCHAR(20) NOT NULL,
    sk_date              INT NOT NULL REFERENCES dim_date(sk_date),
    sk_time_of_day       INT NOT NULL REFERENCES dim_time_of_day(sk_time_of_day),
    sk_power_plant       INT REFERENCES dim_power_plant(sk_power_plant),
    sk_substation        INT REFERENCES dim_substation(sk_substation),
    sk_transmission_line INT REFERENCES dim_transmission_line(sk_transmission_line),
    sk_state             INT REFERENCES dim_state(sk_state),
    sk_occurrence_type   INT NOT NULL REFERENCES dim_occurrence_type(sk_occurrence_type),
    sk_junk_flags        INT NOT NULL REFERENCES dim_junk_flags(sk_junk_flags),
    duration_minutes     DECIMAL(10,2),
    affected_load_mw     DECIMAL(10,2),
    customers_affected   INT,
    CONSTRAINT chk_one_occ_asset CHECK (
        (sk_power_plant IS NOT NULL AND sk_substation IS NULL AND sk_transmission_line IS NULL) OR
        (sk_power_plant IS NULL AND sk_substation IS NOT NULL AND sk_transmission_line IS NULL) OR
        (sk_power_plant IS NULL AND sk_substation IS NULL AND sk_transmission_line IS NOT NULL)
    )
);

-- Unique grain: one row per occurrence per affected asset
CREATE UNIQUE INDEX uq_focc_grain 
    ON fact_grid_occurrence (
        occurrence_id,
        COALESCE(sk_power_plant, -1),
        COALESCE(sk_substation, -1),
        COALESCE(sk_transmission_line, -1)
    );

-- 5.5 Fact_Maintenance (surrogate PK + unique grain index)
CREATE TABLE fact_maintenance (
    sk_maintenance_fact    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    work_order_number      VARCHAR(20) NOT NULL,
    sk_date                INT NOT NULL REFERENCES dim_date(sk_date),
    sk_power_plant         INT REFERENCES dim_power_plant(sk_power_plant),
    sk_substation          INT REFERENCES dim_substation(sk_substation),
    sk_transmission_line   INT REFERENCES dim_transmission_line(sk_transmission_line),
    sk_state               INT REFERENCES dim_state(sk_state),
    sk_maintenance_type    INT NOT NULL REFERENCES dim_maintenance_type(sk_maintenance_type),
    sk_junk_flags          INT NOT NULL REFERENCES dim_junk_flags(sk_junk_flags),
    planned_duration_hours DECIMAL(6,2),
    actual_duration_hours  DECIMAL(6,2),
    cost                   DECIMAL(12,2),
    asset_availability_pct DECIMAL(5,2),
    CONSTRAINT chk_one_maint_asset CHECK (
        (sk_power_plant IS NOT NULL AND sk_substation IS NULL AND sk_transmission_line IS NULL) OR
        (sk_power_plant IS NULL AND sk_substation IS NOT NULL AND sk_transmission_line IS NULL) OR
        (sk_power_plant IS NULL AND sk_substation IS NULL AND sk_transmission_line IS NOT NULL)
    )
);

-- Unique grain: one row per work order per affected asset
CREATE UNIQUE INDEX uq_fmaint_grain 
    ON fact_maintenance (
        work_order_number,
        COALESCE(sk_power_plant, -1),
        COALESCE(sk_substation, -1),
        COALESCE(sk_transmission_line, -1)
    );

-- 5.6 Fact_Asset_Status (surrogate PK + unique grain index)
CREATE TABLE fact_asset_status (
    sk_asset_status_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sk_date               INT NOT NULL REFERENCES dim_date(sk_date),
    sk_power_plant        INT REFERENCES dim_power_plant(sk_power_plant),
    sk_substation         INT REFERENCES dim_substation(sk_substation),
    sk_transmission_line  INT REFERENCES dim_transmission_line(sk_transmission_line),
    sk_state              INT REFERENCES dim_state(sk_state),
    sk_junk_flags         INT NOT NULL REFERENCES dim_junk_flags(sk_junk_flags),
    availability_pct      DECIMAL(5,2),
    asset_age_years       DECIMAL(6,2),
    CONSTRAINT chk_one_asset_status CHECK (
        (sk_power_plant IS NOT NULL AND sk_substation IS NULL AND sk_transmission_line IS NULL) OR
        (sk_power_plant IS NULL AND sk_substation IS NOT NULL AND sk_transmission_line IS NULL) OR
        (sk_power_plant IS NULL AND sk_substation IS NULL AND sk_transmission_line IS NOT NULL)
    )
);

-- Unique grain: one snapshot per asset per day
CREATE UNIQUE INDEX uq_fasset_grain 
    ON fact_asset_status (
        sk_date,
        COALESCE(sk_power_plant, -1),
        COALESCE(sk_substation, -1),
        COALESCE(sk_transmission_line, -1)
    );

-- ============================================================
-- 6. Performance indexes
-- ============================================================
CREATE UNIQUE INDEX uq_dim_state_hash ON dim_state (hash_key_state);
CREATE UNIQUE INDEX uq_dim_power_plant_version
    ON dim_power_plant (hash_key_power_plant, start_date);
CREATE UNIQUE INDEX uq_dim_substation_version
    ON dim_substation (hash_key_substation, start_date);
CREATE UNIQUE INDEX uq_dim_transmission_line_version
    ON dim_transmission_line (hash_key_transmission_line, start_date);
CREATE UNIQUE INDEX uq_dim_occurrence_type_hash
    ON dim_occurrence_type (hash_key_occurrence_type);
CREATE UNIQUE INDEX uq_dim_maintenance_type_hash
    ON dim_maintenance_type (hash_key_maintenance_type);

CREATE INDEX idx_fgen_plant ON fact_energy_generation (sk_power_plant);
CREATE INDEX idx_fgen_state ON fact_energy_generation (sk_state);
CREATE INDEX idx_ftrans_line ON fact_energy_transmission (sk_transmission_line);
CREATE INDEX idx_fmon_sub ON fact_power_system_monitoring (sk_substation);
CREATE INDEX idx_fmon_line ON fact_power_system_monitoring (sk_transmission_line);
CREATE INDEX idx_focc_type ON fact_grid_occurrence (sk_occurrence_type);
CREATE INDEX idx_focc_junk ON fact_grid_occurrence (sk_junk_flags);
CREATE INDEX idx_fmaint_type ON fact_maintenance (sk_maintenance_type);
CREATE INDEX idx_fmaint_junk ON fact_maintenance (sk_junk_flags);
CREATE INDEX idx_fasset_status_date ON fact_asset_status (sk_date);
CREATE INDEX idx_fasset_status_junk ON fact_asset_status (sk_junk_flags);

-- ============================================================
-- 7. Comments
-- ============================================================
COMMENT ON SCHEMA galaxy IS 'Galaxy Schema (Kimball dimensional model) for ONS analytics';
COMMENT ON TABLE dim_date IS 'Date dimension - pre-loaded for full operational horizon';
COMMENT ON TABLE dim_time_of_day IS 'Time-of-day dimension (1440 rows)';
COMMENT ON TABLE dim_state IS 'Brazilian states dimension';
COMMENT ON TABLE dim_power_plant IS 'Power plant dimension (Type 2 SCD)';
COMMENT ON TABLE dim_substation IS 'Substation dimension (Type 2 SCD)';
COMMENT ON TABLE dim_transmission_line IS 'Transmission line dimension (Type 2 SCD)';
COMMENT ON TABLE dim_occurrence_type IS 'Occurrence classification dimension';
COMMENT ON TABLE dim_maintenance_type IS 'Maintenance classification dimension';
COMMENT ON TABLE dim_junk_flags IS 'Junk dimension combining low-cardinality flags (27 rows)';
COMMENT ON TABLE fact_power_system_monitoring IS 'Monitoring fact (surrogate PK, unique grain index)';
COMMENT ON TABLE fact_grid_occurrence IS 'Occurrence fact (surrogate PK, unique grain index)';
COMMENT ON TABLE fact_maintenance IS 'Maintenance fact (surrogate PK, unique grain index)';
COMMENT ON TABLE fact_asset_status IS 'Asset status snapshot (surrogate PK, unique grain index)';
