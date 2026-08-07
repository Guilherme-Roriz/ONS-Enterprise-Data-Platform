WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(occurrence.ticket_number, 'UTF8')), 'hex') AS hash_key_occurrence,
        encode(sha256(convert_to(occurrence_type.type_code, 'UTF8')), 'hex') AS hash_key_occurrence_type,
        occurrence.ticket_number,
        occurrence.start_datetime,
        occurrence.end_datetime,
        occurrence.resolved_flag,
        occurrence.affected_load_mw,
        occurrence.customers_affected,
        CASE
            WHEN occurrence.end_datetime IS NULL THEN NULL
            ELSE EXTRACT(EPOCH FROM (occurrence.end_datetime - occurrence.start_datetime)) / 60
        END AS duration_minutes,
        occurrence.last_updated::date AS effective_date,
        encode(sha256(convert_to(concat_ws('|',
            occurrence_type.type_code,
            occurrence.start_datetime::text,
            COALESCE(occurrence.end_datetime::text, '∅'),
            occurrence.resolved_flag::text,
            COALESCE(occurrence.affected_load_mw::text, '∅'),
            COALESCE(occurrence.customers_affected::text, '∅')
        ), 'UTF8')), 'hex') AS hash_diff
    FROM oltp.occurrence AS occurrence
    JOIN oltp.occurrence_type AS occurrence_type
        ON occurrence_type.occurrence_type_id = occurrence.occurrence_type_id
), hub_load AS (
    INSERT INTO data_vault.hub_occurrence (
        hash_key_occurrence, ticket_number, load_date, record_source
    )
    SELECT hash_key_occurrence, ticket_number, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_occurrence) DO NOTHING
    RETURNING 1
), satellite_close AS (
    UPDATE data_vault.sat_occurrence_detail AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_occurrence = source.hash_key_occurrence
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.hash_diff
    RETURNING 1
), satellite_load AS (
    INSERT INTO data_vault.sat_occurrence_detail (
        hash_key_occurrence, start_date, end_date, hash_key_occurrence_type,
        start_datetime, end_datetime, resolved_flag, affected_load_mw,
        customers_affected, duration_minutes, hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_occurrence, source.effective_date, NULL,
        source.hash_key_occurrence_type, source.start_datetime, source.end_datetime,
        source.resolved_flag, source.affected_load_mw, source.customers_affected,
        source.duration_minutes, source.hash_diff, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM satellite_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1 FROM data_vault.sat_occurrence_detail AS current_row
        WHERE current_row.hash_key_occurrence = source.hash_key_occurrence
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.hash_diff
    )
    ON CONFLICT (hash_key_occurrence, start_date) DO UPDATE SET
        end_date = NULL,
        hash_key_occurrence_type = EXCLUDED.hash_key_occurrence_type,
        start_datetime = EXCLUDED.start_datetime,
        end_datetime = EXCLUDED.end_datetime,
        resolved_flag = EXCLUDED.resolved_flag,
        affected_load_mw = EXCLUDED.affected_load_mw,
        customers_affected = EXCLUDED.customers_affected,
        duration_minutes = EXCLUDED.duration_minutes,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_occurrence_detail.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM satellite_close)
    + (SELECT count(*) FROM satellite_load) AS rows_processed
