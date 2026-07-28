-- ============================================================
-- ONS Enterprise Data Platform – OLTP Schema Creation Script
-- Project: ONS Enterprise Data Platform
-- DBMS: PostgreSQL
-- Version: 1.2 (corrected)
-- Author: Guilherme Roriz
-- Description: Full OLTP schema aligned with OLTP Source System
--              Documentation v1.2. Enforces business rules via
--              CHECK constraints and triggers.
-- ============================================================

-- 1. Schema setup
CREATE SCHEMA IF NOT EXISTS oltp;
SET search_path TO oltp;

-- ============================================================
-- 2. Reference/Domain tables (no FK dependencies)
-- ============================================================

-- 2.1 Brazilian states (UFs)
CREATE TABLE state (
    state_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    state_code      VARCHAR(10) NOT NULL UNIQUE,
    state_name      VARCHAR(50) NOT NULL,
    ons_control_area VARCHAR(50)
);

-- 2.2 Occurrence classification
CREATE TABLE occurrence_type (
    occurrence_type_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_code          VARCHAR(10) NOT NULL UNIQUE,
    category           VARCHAR(30) NOT NULL 
        CHECK (category IN ('Outage','Equipment Failure','Alarm','Emergency')),
    subtype            VARCHAR(50),
    severity_level     VARCHAR(10) NOT NULL 
        CHECK (severity_level IN ('Low','Medium','High','Critical'))
);

-- 2.3 Maintenance classification
CREATE TABLE maintenance_type (
    maintenance_type_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_code           VARCHAR(10) NOT NULL UNIQUE,
    category            VARCHAR(20) NOT NULL 
        CHECK (category IN ('Preventive','Corrective')),
    subtype             VARCHAR(50),
    priority_level      VARCHAR(10) NOT NULL 
        CHECK (priority_level IN ('Low','Medium','High','Urgent'))
);

-- ============================================================
-- 3. Master data tables
-- ============================================================

-- 3.1 Power plants
CREATE TABLE plant (
    plant_id            INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plant_code          VARCHAR(20) NOT NULL UNIQUE,
    plant_name          VARCHAR(100) NOT NULL,
    plant_type          VARCHAR(50) NOT NULL 
        CHECK (plant_type IN ('Hydro','Thermal','Wind','Solar','Nuclear')),
    installed_capacity  DECIMAL(10,2) NOT NULL 
        CHECK (installed_capacity > 0),
    commissioning_date  DATE,
    operator_name       VARCHAR(100),
    state_id            INT NOT NULL 
        REFERENCES state(state_id),
    status              VARCHAR(20) NOT NULL DEFAULT 'Active' 
        CHECK (status IN ('Active','Decommissioned','Under Construction')),
    last_updated        TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 3.2 Substations
CREATE TABLE substation (
    substation_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    substation_code VARCHAR(20) NOT NULL UNIQUE,
    substation_name VARCHAR(100) NOT NULL,
    voltage_level_kv DECIMAL(6,1) NOT NULL 
        CHECK (voltage_level_kv > 0),
    substation_type VARCHAR(30) NOT NULL 
        CHECK (substation_type IN ('Step-up','Step-down','Switching')),
    state_id        INT NOT NULL 
        REFERENCES state(state_id),
    status          VARCHAR(20) NOT NULL DEFAULT 'Active' 
        CHECK (status IN ('Active','Decommissioned','Planned')),
    last_updated    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 3.3 Transmission lines
CREATE TABLE transmission_line (
    line_id                 INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line_code               VARCHAR(20) NOT NULL UNIQUE,
    line_name               VARCHAR(100) NOT NULL,
    voltage_level_kv        DECIMAL(6,1) NOT NULL 
        CHECK (voltage_level_kv > 0),
    length_km               DECIMAL(8,2) NOT NULL 
        CHECK (length_km > 0),
    circuit_type            VARCHAR(10) NOT NULL 
        CHECK (circuit_type IN ('AC','DC')),
    origin_substation_id    INT NOT NULL 
        REFERENCES substation(substation_id),
    destination_substation_id INT NOT NULL 
        REFERENCES substation(substation_id),
    status                  VARCHAR(20) NOT NULL DEFAULT 'Active' 
        CHECK (status IN ('Active','Decommissioned','Planned')),
    last_updated            TIMESTAMP NOT NULL DEFAULT NOW(),
    -- Geographic coordinates
    origin_latitude         DECIMAL(9,6) 
        CHECK (origin_latitude BETWEEN -90 AND 90),
    origin_longitude        DECIMAL(9,6) 
        CHECK (origin_longitude BETWEEN -180 AND 180),
    destination_latitude    DECIMAL(9,6) 
        CHECK (destination_latitude BETWEEN -90 AND 90),
    destination_longitude   DECIMAL(9,6) 
        CHECK (destination_longitude BETWEEN -180 AND 180),
    midpoint_latitude       DECIMAL(9,6) 
        CHECK (midpoint_latitude BETWEEN -90 AND 90),
    midpoint_longitude      DECIMAL(9,6) 
        CHECK (midpoint_longitude BETWEEN -180 AND 180)
);

-- ============================================================
-- 4. Transaction/Event tables
-- ============================================================

-- 4.1 Generation readings (trigger enforces available_capacity <= installed_capacity)
CREATE TABLE generation_reading (
    reading_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plant_id             INT NOT NULL 
        REFERENCES plant(plant_id),
    reading_timestamp    TIMESTAMP NOT NULL,
    generation_output_mw DECIMAL(10,2) NOT NULL 
        CHECK (generation_output_mw >= 0),
    available_capacity_mw DECIMAL(10,2) NOT NULL 
        CHECK (available_capacity_mw >= 0),
    CONSTRAINT uq_gen_reading_plant_time 
        UNIQUE (plant_id, reading_timestamp)
);

-- 4.2 Unified measurement table (polymorphic, with corrected business constraints)
CREATE TABLE measurement (
    measurement_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_type          VARCHAR(20) NOT NULL 
        CHECK (asset_type IN ('substation','transmission_line')),
    asset_id            INT NOT NULL,
    reading_timestamp   TIMESTAMP NOT NULL,
    power_flow_mw       DECIMAL(10,2) 
        CHECK (power_flow_mw >= 0),
    losses_mw           DECIMAL(10,2) 
        CHECK (losses_mw >= 0),
    frequency_hz        DECIMAL(6,2) 
        CHECK (frequency_hz BETWEEN 45.0 AND 65.0),  -- nominal range enforced
    voltage_kv          DECIMAL(6,1) 
        CHECK (voltage_kv > 0),
    system_load_mw      DECIMAL(10,2) 
        CHECK (system_load_mw >= 0),
    reliability_index   DECIMAL(6,4) 
        CHECK (reliability_index BETWEEN 0 AND 1),
    CONSTRAINT uq_measurement_asset_time 
        UNIQUE (asset_type, asset_id, reading_timestamp),
    -- Enforce asset-type-specific nullability for power columns
    CONSTRAINT chk_measurement_asset_logic 
        CHECK (
            (asset_type = 'substation' AND power_flow_mw IS NULL AND losses_mw IS NULL)
            OR 
            (asset_type = 'transmission_line')
        )
);

-- 4.3 Grid occurrences
CREATE TABLE occurrence (
    occurrence_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_number       VARCHAR(20) NOT NULL UNIQUE,
    occurrence_type_id  INT NOT NULL 
        REFERENCES occurrence_type(occurrence_type_id),
    start_datetime      TIMESTAMP NOT NULL,
    end_datetime        TIMESTAMP,
    resolved_flag       BOOLEAN NOT NULL DEFAULT FALSE,
    affected_load_mw    DECIMAL(10,2) 
        CHECK (affected_load_mw >= 0),
    customers_affected  INT 
        CHECK (customers_affected >= 0),
    last_updated        TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 4.4 Occurrence-asset relationship (polymorphic, no FK constraints by design)
CREATE TABLE occurrence_asset (
    occurrence_id   INT NOT NULL 
        REFERENCES occurrence(occurrence_id),
    asset_type      VARCHAR(20) NOT NULL 
        CHECK (asset_type IN ('plant','substation','transmission_line')),
    asset_id        INT NOT NULL,
    PRIMARY KEY (occurrence_id, asset_type, asset_id)
);

-- 4.5 Work orders
CREATE TABLE work_order (
    work_order_id           INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number            VARCHAR(20) NOT NULL UNIQUE,
    maintenance_type_id     INT NOT NULL 
        REFERENCES maintenance_type(maintenance_type_id),
    scheduled_date          DATE,
    planned_duration_hours  DECIMAL(6,2) 
        CHECK (planned_duration_hours > 0),
    actual_duration_hours   DECIMAL(6,2) 
        CHECK (actual_duration_hours >= 0),
    cost                    DECIMAL(12,2) 
        CHECK (cost >= 0),
    overdue_flag            BOOLEAN NOT NULL DEFAULT FALSE,
    asset_availability_pct  DECIMAL(5,2) 
        CHECK (asset_availability_pct BETWEEN 0 AND 100),
    last_updated            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 4.6 Work order-asset relationship (polymorphic)
CREATE TABLE work_order_asset (
    work_order_id   INT NOT NULL 
        REFERENCES work_order(work_order_id),
    asset_type      VARCHAR(20) NOT NULL 
        CHECK (asset_type IN ('plant','substation','transmission_line')),
    asset_id        INT NOT NULL,
    PRIMARY KEY (work_order_id, asset_type, asset_id)
);

-- 4.7 Daily asset status snapshot (polymorphic)
CREATE TABLE asset_status (
    snapshot_date       DATE NOT NULL,
    asset_type          VARCHAR(20) NOT NULL 
        CHECK (asset_type IN ('plant','substation','transmission_line')),
    asset_id            INT NOT NULL,
    availability_pct    DECIMAL(5,2) 
        CHECK (availability_pct BETWEEN 0 AND 100),
    in_operation_flag   BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (snapshot_date, asset_type, asset_id)
);

-- ============================================================
-- 5. Business rule enforcement triggers
-- ============================================================

-- Trigger to ensure available_capacity_mw never exceeds plant.installed_capacity
CREATE OR REPLACE FUNCTION trg_check_available_capacity()
RETURNS TRIGGER AS $$
DECLARE
    installed DECIMAL(10,2);
BEGIN
    SELECT installed_capacity INTO installed
    FROM plant
    WHERE plant_id = NEW.plant_id;

    IF installed IS NULL THEN
        RAISE EXCEPTION 'Plant ID % does not exist', NEW.plant_id;
    END IF;

    IF NEW.available_capacity_mw > installed THEN
        RAISE EXCEPTION 'available_capacity_mw (%) exceeds installed_capacity (%) for plant %', 
            NEW.available_capacity_mw, installed, NEW.plant_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_available_capacity
BEFORE INSERT OR UPDATE ON generation_reading
FOR EACH ROW EXECUTE FUNCTION trg_check_available_capacity();

-- ============================================================
-- 6. Performance indexes
-- ============================================================

CREATE INDEX idx_gen_reading_plant_time 
    ON generation_reading (plant_id, reading_timestamp DESC);

CREATE INDEX idx_measurement_asset_time 
    ON measurement (asset_type, asset_id, reading_timestamp DESC);

CREATE INDEX idx_occurrence_start 
    ON occurrence (start_datetime DESC);
CREATE INDEX idx_occurrence_type 
    ON occurrence (occurrence_type_id);

CREATE INDEX idx_work_order_date 
    ON work_order (scheduled_date);
CREATE INDEX idx_work_order_type 
    ON work_order (maintenance_type_id);

CREATE INDEX idx_asset_status_date 
    ON asset_status (snapshot_date DESC);

CREATE INDEX idx_occurrence_asset_asset 
    ON occurrence_asset (asset_type, asset_id);

CREATE INDEX idx_work_order_asset_asset 
    ON work_order_asset (asset_type, asset_id);

-- ============================================================
-- 7. Table and column comments
-- ============================================================

COMMENT ON TABLE state IS 'Brazilian states (UFs) - reference table';
COMMENT ON TABLE occurrence_type IS 'Classification of grid occurrences';
COMMENT ON TABLE maintenance_type IS 'Classification of maintenance activities';
COMMENT ON TABLE plant IS 'Power plant master data';
COMMENT ON TABLE substation IS 'Substation master data';
COMMENT ON TABLE transmission_line IS 'Transmission line master data';
COMMENT ON TABLE generation_reading IS 'Minute-level generation measurements per plant';
COMMENT ON TABLE measurement IS 'Minute-level electric measurements at substations and transmission lines (polymorphic)';
COMMENT ON TABLE occurrence IS 'Grid incidents, outages, alarms and emergency events';
COMMENT ON TABLE occurrence_asset IS 'Links an occurrence to affected assets (polymorphic)';
COMMENT ON TABLE work_order IS 'Preventive and corrective maintenance activities';
COMMENT ON TABLE work_order_asset IS 'Links a work order to affected assets (polymorphic)';
COMMENT ON TABLE asset_status IS 'Daily snapshot of operational status and availability per asset';