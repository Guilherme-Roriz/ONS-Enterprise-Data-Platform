WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(substation.substation_code, 'UTF8')), 'hex') AS hash_key_substation,
        encode(sha256(convert_to(state.state_code, 'UTF8')), 'hex') AS hash_key_state,
        substation.substation_code,
        substation.substation_name,
        substation.voltage_level_kv,
        substation.substation_type,
        substation.status,
        substation.last_updated::date AS effective_date,
        encode(sha256(convert_to(concat_ws('|',
            substation.substation_name,
            substation.voltage_level_kv::text,
            substation.substation_type
        ), 'UTF8')), 'hex') AS attributes_hash_diff,
        encode(sha256(convert_to(substation.status, 'UTF8')), 'hex') AS status_hash_diff
    FROM oltp.substation AS substation
    JOIN oltp.state AS state ON state.state_id = substation.state_id
), hub_load AS (
    INSERT INTO data_vault.hub_substation (
        hash_key_substation, substation_code, load_date, record_source
    )
    SELECT hash_key_substation, substation_code, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_substation) DO NOTHING
    RETURNING 1
), attributes_close AS (
    UPDATE data_vault.sat_substation_attributes AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_substation = source.hash_key_substation
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.attributes_hash_diff
    RETURNING 1
), attributes_load AS (
    INSERT INTO data_vault.sat_substation_attributes (
        hash_key_substation, start_date, end_date, substation_name,
        voltage_level_kv, substation_type, hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_substation, source.effective_date, NULL,
        source.substation_name, source.voltage_level_kv, source.substation_type,
        source.attributes_hash_diff, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM attributes_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1 FROM data_vault.sat_substation_attributes AS current_row
        WHERE current_row.hash_key_substation = source.hash_key_substation
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.attributes_hash_diff
    )
    ON CONFLICT (hash_key_substation, start_date) DO UPDATE SET
        end_date = NULL,
        substation_name = EXCLUDED.substation_name,
        voltage_level_kv = EXCLUDED.voltage_level_kv,
        substation_type = EXCLUDED.substation_type,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_substation_attributes.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
), status_close AS (
    UPDATE data_vault.sat_substation_status AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_substation = source.hash_key_substation
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.status_hash_diff
    RETURNING 1
), status_load AS (
    INSERT INTO data_vault.sat_substation_status (
        hash_key_substation, start_date, end_date, status,
        hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_substation, source.effective_date, NULL, source.status,
        source.status_hash_diff, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM status_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1 FROM data_vault.sat_substation_status AS current_row
        WHERE current_row.hash_key_substation = source.hash_key_substation
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.status_hash_diff
    )
    ON CONFLICT (hash_key_substation, start_date) DO UPDATE SET
        end_date = NULL,
        status = EXCLUDED.status,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_substation_status.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
), link_load AS (
    INSERT INTO data_vault.link_substation_state (
        hash_key_link_substation_state, hash_key_substation, hash_key_state,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(source.hash_key_substation, source.hash_key_state), 'UTF8')), 'hex'),
        source.hash_key_substation, source.hash_key_state,
        CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS dependency
    ON CONFLICT (hash_key_link_substation_state) DO NOTHING
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM attributes_close)
    + (SELECT count(*) FROM attributes_load)
    + (SELECT count(*) FROM status_close)
    + (SELECT count(*) FROM status_load)
    + (SELECT count(*) FROM link_load) AS rows_processed
