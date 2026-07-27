-- ============================================================
-- ONS Enterprise Data Platform – Raw Data Vault DDL
-- Schema: data_vault
-- Hash algorithm: SHA-256 (CHAR(64))
-- Version: 1.2 (corrected)
-- Corrections:
--   - Added UNIQUE constraints on all hub business keys
--   - Changed sat_occurrence_detail and sat_work_order_detail
--     to full SCD2 (start_date/end_date, PK on hash + start_date)
-- ============================================================

CREATE SCHEMA IF NOT EXISTS data_vault;
SET search_path TO data_vault;

-- ============================================================
-- 3. Hubs
-- ============================================================

CREATE TABLE hub_power_plant (
    hash_key_power_plant CHAR(64) PRIMARY KEY,
    plant_code           VARCHAR(20) NOT NULL UNIQUE,
    load_date            TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source        VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_transmission_line (
    hash_key_transmission_line CHAR(64) PRIMARY KEY,
    line_code                  VARCHAR(20) NOT NULL UNIQUE,
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_substation (
    hash_key_substation CHAR(64) PRIMARY KEY,
    substation_code     VARCHAR(20) NOT NULL UNIQUE,
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_occurrence (
    hash_key_occurrence CHAR(64) PRIMARY KEY,
    ticket_number       VARCHAR(20) NOT NULL UNIQUE,
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_work_order (
    hash_key_work_order CHAR(64) PRIMARY KEY,
    order_number        VARCHAR(20) NOT NULL UNIQUE,
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_state (
    hash_key_state CHAR(64) PRIMARY KEY,
    state_code     VARCHAR(10) NOT NULL UNIQUE,
    load_date      TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source  VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_occurrence_type (
    hash_key_occurrence_type CHAR(64) PRIMARY KEY,
    type_code                VARCHAR(10) NOT NULL UNIQUE,
    load_date                TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source            VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE hub_maintenance_type (
    hash_key_maintenance_type CHAR(64) PRIMARY KEY,
    type_code                 VARCHAR(10) NOT NULL UNIQUE,
    load_date                 TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source             VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

-- ============================================================
-- 4. Links
-- ============================================================

CREATE TABLE link_occurrence_power_plant (
    hash_key_link_occ_plant CHAR(64) PRIMARY KEY,
    hash_key_occurrence     CHAR(64) NOT NULL REFERENCES hub_occurrence(hash_key_occurrence),
    hash_key_power_plant    CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    load_date               TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source           VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_occurrence_substation (
    hash_key_link_occ_sub CHAR(64) PRIMARY KEY,
    hash_key_occurrence   CHAR(64) NOT NULL REFERENCES hub_occurrence(hash_key_occurrence),
    hash_key_substation   CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    load_date             TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source         VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_occurrence_transmission_line (
    hash_key_link_occ_line     CHAR(64) PRIMARY KEY,
    hash_key_occurrence        CHAR(64) NOT NULL REFERENCES hub_occurrence(hash_key_occurrence),
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_work_order_power_plant (
    hash_key_link_wo_plant CHAR(64) PRIMARY KEY,
    hash_key_work_order    CHAR(64) NOT NULL REFERENCES hub_work_order(hash_key_work_order),
    hash_key_power_plant   CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    load_date              TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source          VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_work_order_substation (
    hash_key_link_wo_sub CHAR(64) PRIMARY KEY,
    hash_key_work_order  CHAR(64) NOT NULL REFERENCES hub_work_order(hash_key_work_order),
    hash_key_substation  CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    load_date            TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source        VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_work_order_transmission_line (
    hash_key_link_wo_line      CHAR(64) PRIMARY KEY,
    hash_key_work_order        CHAR(64) NOT NULL REFERENCES hub_work_order(hash_key_work_order),
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_power_plant_state (
    hash_key_link_plant_state CHAR(64) PRIMARY KEY,
    hash_key_power_plant      CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    hash_key_state            CHAR(64) NOT NULL REFERENCES hub_state(hash_key_state),
    load_date                 TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source             VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_substation_state (
    hash_key_link_substation_state CHAR(64) PRIMARY KEY,
    hash_key_substation            CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    hash_key_state                 CHAR(64) NOT NULL REFERENCES hub_state(hash_key_state),
    load_date                      TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source                  VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

CREATE TABLE link_transmission_line_substation (
    hash_key_link_line_sub     CHAR(64) PRIMARY KEY,
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    hash_key_substation        CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    role_code                  VARCHAR(20) NOT NULL CHECK (role_code IN ('ORIGIN','DESTINATION')),
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP'
);

-- ============================================================
-- 5. Satellites
-- ============================================================

-- Power Plant Satellites
CREATE TABLE sat_power_plant_attributes (
    hash_key_power_plant CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    start_date           DATE NOT NULL,
    end_date             DATE,
    plant_name           VARCHAR(100),
    plant_type           VARCHAR(50),
    installed_capacity_mw DECIMAL(10,2),
    commissioning_date   DATE,
    operator_name        VARCHAR(100),
    hash_diff            CHAR(64) NOT NULL,
    load_date            TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source        VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_power_plant, start_date)
);

CREATE TABLE sat_power_plant_status (
    hash_key_power_plant CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    start_date           DATE NOT NULL,
    end_date             DATE,
    status               VARCHAR(20) NOT NULL,
    hash_diff            CHAR(64) NOT NULL,
    load_date            TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source        VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_power_plant, start_date)
);

CREATE TABLE sat_power_plant_daily_snapshot (
    hash_key_power_plant CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    snapshot_date        DATE NOT NULL,
    availability_pct     DECIMAL(5,2),
    in_operation_flag    BOOLEAN,
    load_date            TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source        VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_power_plant, snapshot_date)
);

-- Transmission Line Satellites
CREATE TABLE sat_line_attributes (
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    start_date                 DATE NOT NULL,
    end_date                   DATE,
    line_code                  VARCHAR(20),
    voltage_level_kv           DECIMAL(6,1),
    length_km                  DECIMAL(8,2),
    circuit_type               VARCHAR(10),
    origin_latitude            DECIMAL(9,6),
    origin_longitude           DECIMAL(9,6),
    destination_latitude       DECIMAL(9,6),
    destination_longitude      DECIMAL(9,6),
    midpoint_latitude          DECIMAL(9,6),
    midpoint_longitude         DECIMAL(9,6),
    hash_diff                  CHAR(64) NOT NULL,
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_transmission_line, start_date)
);

CREATE TABLE sat_line_status (
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    start_date                 DATE NOT NULL,
    end_date                   DATE,
    status                     VARCHAR(20) NOT NULL,
    hash_diff                  CHAR(64) NOT NULL,
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_transmission_line, start_date)
);

CREATE TABLE sat_line_daily_snapshot (
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    snapshot_date              DATE NOT NULL,
    availability_pct           DECIMAL(5,2),
    in_operation_flag          BOOLEAN,
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_transmission_line, snapshot_date)
);

-- Substation Satellites
CREATE TABLE sat_substation_attributes (
    hash_key_substation CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    start_date          DATE NOT NULL,
    end_date            DATE,
    substation_name     VARCHAR(100),
    voltage_level_kv    DECIMAL(6,1),
    substation_type     VARCHAR(30),
    hash_diff           CHAR(64) NOT NULL,
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_substation, start_date)
);

CREATE TABLE sat_substation_status (
    hash_key_substation CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    start_date          DATE NOT NULL,
    end_date            DATE,
    status              VARCHAR(20) NOT NULL,
    hash_diff           CHAR(64) NOT NULL,
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_substation, start_date)
);

CREATE TABLE sat_substation_daily_snapshot (
    hash_key_substation CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    snapshot_date       DATE NOT NULL,
    availability_pct    DECIMAL(5,2),
    in_operation_flag   BOOLEAN,
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_substation, snapshot_date)
);

-- Occurrence Satellite (SCD2)
CREATE TABLE sat_occurrence_detail (
    hash_key_occurrence      CHAR(64) NOT NULL REFERENCES hub_occurrence(hash_key_occurrence),
    start_date               DATE NOT NULL,
    end_date                 DATE,
    hash_key_occurrence_type CHAR(64) NOT NULL REFERENCES hub_occurrence_type(hash_key_occurrence_type),
    start_datetime           TIMESTAMP NOT NULL,
    end_datetime             TIMESTAMP,
    resolved_flag            BOOLEAN NOT NULL DEFAULT FALSE,
    affected_load_mw         DECIMAL(10,2),
    customers_affected       INT,
    duration_minutes         DECIMAL,
    hash_diff                CHAR(64) NOT NULL,
    load_date                TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source            VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_occurrence, start_date)
);

-- Work Order Satellite (SCD2)
CREATE TABLE sat_work_order_detail (
    hash_key_work_order       CHAR(64) NOT NULL REFERENCES hub_work_order(hash_key_work_order),
    start_date                DATE NOT NULL,
    end_date                  DATE,
    hash_key_maintenance_type CHAR(64) NOT NULL REFERENCES hub_maintenance_type(hash_key_maintenance_type),
    scheduled_date            DATE,
    planned_duration_hours    DECIMAL(6,2),
    actual_duration_hours     DECIMAL(6,2),
    cost                      DECIMAL(12,2),
    overdue_flag              BOOLEAN NOT NULL DEFAULT FALSE,
    asset_availability_pct    DECIMAL(5,2),
    hash_diff                 CHAR(64) NOT NULL,
    load_date                 TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source             VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_work_order, start_date)
);

-- State Satellite (SCD1)
CREATE TABLE sat_state_attributes (
    hash_key_state   CHAR(64) NOT NULL REFERENCES hub_state(hash_key_state),
    state_name       VARCHAR(50),
    ons_control_area VARCHAR(50),
    hash_diff        CHAR(64) NOT NULL,
    load_date        TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source    VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_state)
);

-- Occurrence Type Satellite (SCD1)
CREATE TABLE sat_occurrence_type_attributes (
    hash_key_occurrence_type CHAR(64) NOT NULL REFERENCES hub_occurrence_type(hash_key_occurrence_type),
    category                 VARCHAR(30),
    subtype                  VARCHAR(50),
    severity_level           VARCHAR(10),
    hash_diff                CHAR(64) NOT NULL,
    load_date                TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source            VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_occurrence_type)
);

-- Maintenance Type Satellite (SCD1)
CREATE TABLE sat_maintenance_type_attributes (
    hash_key_maintenance_type CHAR(64) NOT NULL REFERENCES hub_maintenance_type(hash_key_maintenance_type),
    category                  VARCHAR(20),
    subtype                   VARCHAR(50),
    priority_level            VARCHAR(10),
    hash_diff                 CHAR(64) NOT NULL,
    load_date                 TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source             VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_maintenance_type)
);

-- Transactional (append-only) satellites
CREATE TABLE sat_gen_reading (
    hash_key_power_plant  CHAR(64) NOT NULL REFERENCES hub_power_plant(hash_key_power_plant),
    reading_timestamp     TIMESTAMP NOT NULL,
    generation_output_mw  DECIMAL(10,2) NOT NULL,
    available_capacity_mw DECIMAL(10,2) NOT NULL,
    load_date             TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source         VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_power_plant, reading_timestamp)
);

CREATE TABLE sat_substation_measurement (
    hash_key_substation CHAR(64) NOT NULL REFERENCES hub_substation(hash_key_substation),
    reading_timestamp   TIMESTAMP NOT NULL,
    frequency_hz        DECIMAL(6,2),
    voltage_kv          DECIMAL(6,1),
    system_load_mw      DECIMAL(10,2),
    reliability_index   DECIMAL(6,4),
    load_date           TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source       VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_substation, reading_timestamp)
);

CREATE TABLE sat_line_measurement (
    hash_key_transmission_line CHAR(64) NOT NULL REFERENCES hub_transmission_line(hash_key_transmission_line),
    reading_timestamp          TIMESTAMP NOT NULL,
    power_flow_mw              DECIMAL(10,2),
    losses_mw                  DECIMAL(10,2),
    frequency_hz               DECIMAL(6,2),
    voltage_kv                 DECIMAL(6,1),
    load_date                  TIMESTAMP NOT NULL DEFAULT NOW(),
    record_source              VARCHAR(50) NOT NULL DEFAULT 'ONS_OLTP',
    PRIMARY KEY (hash_key_transmission_line, reading_timestamp)
);

-- ============================================================
-- 6. Comments
-- ============================================================

COMMENT ON SCHEMA data_vault IS 'Raw Data Vault layer for ONS Enterprise Data Platform';
COMMENT ON TABLE hub_power_plant IS 'Hub for power plants';
COMMENT ON TABLE hub_transmission_line IS 'Hub for transmission lines';
COMMENT ON TABLE hub_substation IS 'Hub for substations';
COMMENT ON TABLE hub_occurrence IS 'Hub for grid occurrences';
COMMENT ON TABLE hub_work_order IS 'Hub for work orders';
COMMENT ON TABLE hub_state IS 'Hub for Brazilian states';
COMMENT ON TABLE hub_occurrence_type IS 'Hub for occurrence types';
COMMENT ON TABLE hub_maintenance_type IS 'Hub for maintenance types';