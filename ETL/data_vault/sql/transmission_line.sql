WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(line.line_code, 'UTF8')), 'hex') AS hash_key_transmission_line,
        encode(sha256(convert_to(origin.substation_code, 'UTF8')), 'hex') AS hash_key_origin_substation,
        encode(sha256(convert_to(destination.substation_code, 'UTF8')), 'hex') AS hash_key_destination_substation,
        line.line_code,
        line.voltage_level_kv,
        line.length_km,
        line.circuit_type,
        line.origin_latitude,
        line.origin_longitude,
        line.destination_latitude,
        line.destination_longitude,
        line.midpoint_latitude,
        line.midpoint_longitude,
        line.status,
        line.last_updated::date AS effective_date,
        encode(sha256(convert_to(concat_ws('|',
            line.line_code,
            line.voltage_level_kv::text,
            line.length_km::text,
            line.circuit_type,
            COALESCE(line.origin_latitude::text, '∅'),
            COALESCE(line.origin_longitude::text, '∅'),
            COALESCE(line.destination_latitude::text, '∅'),
            COALESCE(line.destination_longitude::text, '∅'),
            COALESCE(line.midpoint_latitude::text, '∅'),
            COALESCE(line.midpoint_longitude::text, '∅')
        ), 'UTF8')), 'hex') AS attributes_hash_diff,
        encode(sha256(convert_to(line.status, 'UTF8')), 'hex') AS status_hash_diff
    FROM oltp.transmission_line AS line
    JOIN oltp.substation AS origin
        ON origin.substation_id = line.origin_substation_id
    JOIN oltp.substation AS destination
        ON destination.substation_id = line.destination_substation_id
), hub_load AS (
    INSERT INTO data_vault.hub_transmission_line (
        hash_key_transmission_line, line_code, load_date, record_source
    )
    SELECT hash_key_transmission_line, line_code, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_transmission_line) DO NOTHING
    RETURNING 1
), attributes_close AS (
    UPDATE data_vault.sat_line_attributes AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_transmission_line = source.hash_key_transmission_line
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.attributes_hash_diff
    RETURNING 1
), attributes_load AS (
    INSERT INTO data_vault.sat_line_attributes (
        hash_key_transmission_line, start_date, end_date, line_code,
        voltage_level_kv, length_km, circuit_type, origin_latitude,
        origin_longitude, destination_latitude, destination_longitude,
        midpoint_latitude, midpoint_longitude, hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_transmission_line, source.effective_date, NULL,
        source.line_code, source.voltage_level_kv, source.length_km,
        source.circuit_type, source.origin_latitude, source.origin_longitude,
        source.destination_latitude, source.destination_longitude,
        source.midpoint_latitude, source.midpoint_longitude,
        source.attributes_hash_diff, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM attributes_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1 FROM data_vault.sat_line_attributes AS current_row
        WHERE current_row.hash_key_transmission_line = source.hash_key_transmission_line
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.attributes_hash_diff
    )
    ON CONFLICT (hash_key_transmission_line, start_date) DO UPDATE SET
        end_date = NULL,
        line_code = EXCLUDED.line_code,
        voltage_level_kv = EXCLUDED.voltage_level_kv,
        length_km = EXCLUDED.length_km,
        circuit_type = EXCLUDED.circuit_type,
        origin_latitude = EXCLUDED.origin_latitude,
        origin_longitude = EXCLUDED.origin_longitude,
        destination_latitude = EXCLUDED.destination_latitude,
        destination_longitude = EXCLUDED.destination_longitude,
        midpoint_latitude = EXCLUDED.midpoint_latitude,
        midpoint_longitude = EXCLUDED.midpoint_longitude,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_line_attributes.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
), status_close AS (
    UPDATE data_vault.sat_line_status AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_transmission_line = source.hash_key_transmission_line
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.status_hash_diff
    RETURNING 1
), status_load AS (
    INSERT INTO data_vault.sat_line_status (
        hash_key_transmission_line, start_date, end_date, status,
        hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_transmission_line, source.effective_date, NULL,
        source.status, source.status_hash_diff, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM status_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1 FROM data_vault.sat_line_status AS current_row
        WHERE current_row.hash_key_transmission_line = source.hash_key_transmission_line
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.status_hash_diff
    )
    ON CONFLICT (hash_key_transmission_line, start_date) DO UPDATE SET
        end_date = NULL,
        status = EXCLUDED.status,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_line_status.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
), origin_link_load AS (
    INSERT INTO data_vault.link_transmission_line_substation (
        hash_key_link_line_sub, hash_key_transmission_line,
        hash_key_substation, role_code, load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(
            source.hash_key_transmission_line,
            source.hash_key_origin_substation,
            'ORIGIN'
        ), 'UTF8')), 'hex'),
        source.hash_key_transmission_line,
        source.hash_key_origin_substation,
        'ORIGIN',
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS dependency
    ON CONFLICT (hash_key_link_line_sub) DO NOTHING
    RETURNING 1
), destination_link_load AS (
    INSERT INTO data_vault.link_transmission_line_substation (
        hash_key_link_line_sub, hash_key_transmission_line,
        hash_key_substation, role_code, load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(
            source.hash_key_transmission_line,
            source.hash_key_destination_substation,
            'DESTINATION'
        ), 'UTF8')), 'hex'),
        source.hash_key_transmission_line,
        source.hash_key_destination_substation,
        'DESTINATION',
        CURRENT_TIMESTAMP,
        'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM origin_link_load) AS dependency
    ON CONFLICT (hash_key_link_line_sub) DO NOTHING
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM attributes_close)
    + (SELECT count(*) FROM attributes_load)
    + (SELECT count(*) FROM status_close)
    + (SELECT count(*) FROM status_load)
    + (SELECT count(*) FROM origin_link_load)
    + (SELECT count(*) FROM destination_link_load) AS rows_processed
