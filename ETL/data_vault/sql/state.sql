WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(state_code, 'UTF8')), 'hex') AS hash_key_state,
        state_code,
        state_name,
        ons_control_area,
        encode(
            sha256(convert_to(concat_ws('|', state_name, COALESCE(ons_control_area, '∅')), 'UTF8')),
            'hex'
        ) AS hash_diff
    FROM oltp.state
), hub_load AS (
    INSERT INTO data_vault.hub_state (
        hash_key_state, state_code, load_date, record_source
    )
    SELECT hash_key_state, state_code, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_state) DO NOTHING
    RETURNING 1
), satellite_load AS (
    INSERT INTO data_vault.sat_state_attributes (
        hash_key_state, state_name, ons_control_area,
        hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_state,
        source.state_name,
        source.ons_control_area,
        source.hash_diff,
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS dependency
    ON CONFLICT (hash_key_state) DO UPDATE SET
        state_name = EXCLUDED.state_name,
        ons_control_area = EXCLUDED.ons_control_area,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_state_attributes.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM satellite_load) AS rows_processed
