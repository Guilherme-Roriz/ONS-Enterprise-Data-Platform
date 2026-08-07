-- Upgrade an existing Data Vault v1.2 schema for the corrected OLTP -> Data Vault ETL.
-- Resolve any duplicate open satellite rows before running this migration.

CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_power_plant_attributes_current
    ON data_vault.sat_power_plant_attributes (hash_key_power_plant)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_power_plant_status_current
    ON data_vault.sat_power_plant_status (hash_key_power_plant)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_line_attributes_current
    ON data_vault.sat_line_attributes (hash_key_transmission_line)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_line_status_current
    ON data_vault.sat_line_status (hash_key_transmission_line)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_substation_attributes_current
    ON data_vault.sat_substation_attributes (hash_key_substation)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_substation_status_current
    ON data_vault.sat_substation_status (hash_key_substation)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_occurrence_detail_current
    ON data_vault.sat_occurrence_detail (hash_key_occurrence)
    WHERE end_date IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sat_work_order_detail_current
    ON data_vault.sat_work_order_detail (hash_key_work_order)
    WHERE end_date IS NULL;
