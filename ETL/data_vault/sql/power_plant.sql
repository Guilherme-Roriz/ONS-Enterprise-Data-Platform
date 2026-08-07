WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(plant.plant_code, 'UTF8')), 'hex') AS hash_key_power_plant,
        encode(sha256(convert_to(state.state_code, 'UTF8')), 'hex') AS hash_key_state,
        plant.plant_code,
        plant.plant_name,
        plant.plant_type,
        plant.installed_capacity AS installed_capacity_mw,
        plant.commissioning_date,
        plant.operator_name,
        plant.status,
        plant.last_updated::date AS effective_date,
        encode(sha256(convert_to(concat_ws('|',
            plant.plant_name,
            plant.plant_type,
            plant.installed_capacity::text,
            COALESCE(plant.commissioning_date::text, '∅'),
            COALESCE(plant.operator_name, '∅')
        ), 'UTF8')), 'hex') AS attributes_hash_diff,
        encode(sha256(convert_to(plant.status, 'UTF8')), 'hex') AS status_hash_diff
    FROM oltp.plant AS plant
    JOIN oltp.state AS state ON state.state_id = plant.state_id
), hub_load AS (
    INSERT INTO data_vault.hub_power_plant (
        hash_key_power_plant, plant_code, load_date, record_source
    )
    SELECT hash_key_power_plant, plant_code, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_power_plant) DO NOTHING
    RETURNING 1
), attributes_close AS (
    UPDATE data_vault.sat_power_plant_attributes AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_power_plant = source.hash_key_power_plant
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.attributes_hash_diff
    RETURNING 1
), attributes_load AS (
    INSERT INTO data_vault.sat_power_plant_attributes (
        hash_key_power_plant, start_date, end_date, plant_name, plant_type,
        installed_capacity_mw, commissioning_date, operator_name,
        hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_power_plant,
        source.effective_date,
        NULL,
        source.plant_name,
        source.plant_type,
        source.installed_capacity_mw,
        source.commissioning_date,
        source.operator_name,
        source.attributes_hash_diff,
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM attributes_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1
        FROM data_vault.sat_power_plant_attributes AS current_row
        WHERE current_row.hash_key_power_plant = source.hash_key_power_plant
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.attributes_hash_diff
    )
    ON CONFLICT (hash_key_power_plant, start_date) DO UPDATE SET
        end_date = NULL,
        plant_name = EXCLUDED.plant_name,
        plant_type = EXCLUDED.plant_type,
        installed_capacity_mw = EXCLUDED.installed_capacity_mw,
        commissioning_date = EXCLUDED.commissioning_date,
        operator_name = EXCLUDED.operator_name,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_power_plant_attributes.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
), status_close AS (
    UPDATE data_vault.sat_power_plant_status AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_power_plant = source.hash_key_power_plant
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.status_hash_diff
    RETURNING 1
), status_load AS (
    INSERT INTO data_vault.sat_power_plant_status (
        hash_key_power_plant, start_date, end_date, status,
        hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_power_plant,
        source.effective_date,
        NULL,
        source.status,
        source.status_hash_diff,
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM status_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1
        FROM data_vault.sat_power_plant_status AS current_row
        WHERE current_row.hash_key_power_plant = source.hash_key_power_plant
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.status_hash_diff
    )
    ON CONFLICT (hash_key_power_plant, start_date) DO UPDATE SET
        end_date = NULL,
        status = EXCLUDED.status,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_power_plant_status.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
), link_load AS (
    INSERT INTO data_vault.link_power_plant_state (
        hash_key_link_plant_state, hash_key_power_plant, hash_key_state,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(source.hash_key_power_plant, source.hash_key_state), 'UTF8')), 'hex'),
        source.hash_key_power_plant,
        source.hash_key_state,
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS dependency
    ON CONFLICT (hash_key_link_plant_state) DO NOTHING
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM attributes_close)
    + (SELECT count(*) FROM attributes_load)
    + (SELECT count(*) FROM status_close)
    + (SELECT count(*) FROM status_load)
    + (SELECT count(*) FROM link_load) AS rows_processed
