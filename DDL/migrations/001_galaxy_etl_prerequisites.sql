-- Upgrade an existing Galaxy v1.7 schema for the Data Vault -> Galaxy ETL.
-- New installations already receive these changes from fact_constelation.sql.

CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_state_hash
    ON galaxy.dim_state (hash_key_state);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_power_plant_version
    ON galaxy.dim_power_plant (hash_key_power_plant, start_date);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_substation_version
    ON galaxy.dim_substation (hash_key_substation, start_date);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_transmission_line_version
    ON galaxy.dim_transmission_line (hash_key_transmission_line, start_date);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_occurrence_type_hash
    ON galaxy.dim_occurrence_type (hash_key_occurrence_type);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dim_maintenance_type_hash
    ON galaxy.dim_maintenance_type (hash_key_maintenance_type);

ALTER TABLE galaxy.fact_energy_generation
    ALTER COLUMN capacity_factor_pct TYPE DECIMAL(7,4);
ALTER TABLE galaxy.fact_energy_transmission
    ALTER COLUMN line_loading_pct TYPE DECIMAL(7,4);
