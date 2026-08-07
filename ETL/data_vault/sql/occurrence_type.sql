WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(type_code, 'UTF8')), 'hex') AS hash_key_occurrence_type,
        type_code,
        category,
        subtype,
        severity_level,
        encode(
            sha256(convert_to(concat_ws('|', category, COALESCE(subtype, '∅'), severity_level), 'UTF8')),
            'hex'
        ) AS hash_diff
    FROM oltp.occurrence_type
), hub_load AS (
    INSERT INTO data_vault.hub_occurrence_type (
        hash_key_occurrence_type, type_code, load_date, record_source
    )
    SELECT hash_key_occurrence_type, type_code, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_occurrence_type) DO NOTHING
    RETURNING 1
), satellite_load AS (
    INSERT INTO data_vault.sat_occurrence_type_attributes (
        hash_key_occurrence_type, category, subtype, severity_level,
        hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_occurrence_type,
        source.category,
        source.subtype,
        source.severity_level,
        source.hash_diff,
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS dependency
    ON CONFLICT (hash_key_occurrence_type) DO UPDATE SET
        category = EXCLUDED.category,
        subtype = EXCLUDED.subtype,
        severity_level = EXCLUDED.severity_level,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_occurrence_type_attributes.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM satellite_load) AS rows_processed
