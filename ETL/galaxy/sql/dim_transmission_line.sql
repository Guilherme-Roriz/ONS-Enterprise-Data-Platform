WITH boundaries AS (
    SELECT hash_key_transmission_line, start_date
    FROM data_vault.sat_line_attributes
    UNION
    SELECT hash_key_transmission_line, start_date
    FROM data_vault.sat_line_status
), versions AS (
    SELECT
        boundary.hash_key_transmission_line,
        boundary.start_date,
        attributes.line_code,
        attributes.voltage_level_kv,
        attributes.length_km,
        attributes.circuit_type,
        attributes.origin_latitude,
        attributes.origin_longitude,
        attributes.destination_latitude,
        attributes.destination_longitude,
        attributes.midpoint_latitude,
        attributes.midpoint_longitude,
        status.status,
        origin_substation.substation_name AS origin_substation_name,
        destination_substation.substation_name AS destination_substation_name
    FROM boundaries AS boundary
    LEFT JOIN LATERAL (
        SELECT sat.*
        FROM data_vault.sat_line_attributes AS sat
        WHERE sat.hash_key_transmission_line = boundary.hash_key_transmission_line
          AND sat.start_date <= boundary.start_date
          AND (sat.end_date IS NULL OR boundary.start_date < sat.end_date)
        ORDER BY sat.start_date DESC
        LIMIT 1
    ) AS attributes ON TRUE
    LEFT JOIN LATERAL (
        SELECT sat.status
        FROM data_vault.sat_line_status AS sat
        WHERE sat.hash_key_transmission_line = boundary.hash_key_transmission_line
          AND sat.start_date <= boundary.start_date
          AND (sat.end_date IS NULL OR boundary.start_date < sat.end_date)
        ORDER BY sat.start_date DESC
        LIMIT 1
    ) AS status ON TRUE
    LEFT JOIN LATERAL (
        SELECT link.hash_key_substation
        FROM data_vault.link_transmission_line_substation AS link
        WHERE link.hash_key_transmission_line = boundary.hash_key_transmission_line
          AND link.role_code = 'ORIGIN'
        ORDER BY link.load_date DESC
        LIMIT 1
    ) AS origin_link ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.substation_name
        FROM galaxy.dim_substation AS dim
        WHERE dim.hash_key_substation = origin_link.hash_key_substation
          AND dim.start_date <= boundary.start_date
          AND (dim.end_date IS NULL OR boundary.start_date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS origin_substation ON TRUE
    LEFT JOIN LATERAL (
        SELECT link.hash_key_substation
        FROM data_vault.link_transmission_line_substation AS link
        WHERE link.hash_key_transmission_line = boundary.hash_key_transmission_line
          AND link.role_code = 'DESTINATION'
        ORDER BY link.load_date DESC
        LIMIT 1
    ) AS destination_link ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.substation_name
        FROM galaxy.dim_substation AS dim
        WHERE dim.hash_key_substation = destination_link.hash_key_substation
          AND dim.start_date <= boundary.start_date
          AND (dim.end_date IS NULL OR boundary.start_date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS destination_substation ON TRUE
), marked AS (
    SELECT
        versions.*,
        CASE
            WHEN row_number() OVER (
                PARTITION BY hash_key_transmission_line ORDER BY start_date
            ) = 1 THEN 1
            WHEN ROW(voltage_level_kv, status)
                 IS DISTINCT FROM lag(ROW(voltage_level_kv, status)) OVER (
                     PARTITION BY hash_key_transmission_line ORDER BY start_date
                 ) THEN 1
            ELSE 0
        END AS is_new_version
    FROM versions
), grouped AS (
    SELECT
        marked.*,
        sum(is_new_version) OVER (
            PARTITION BY hash_key_transmission_line ORDER BY start_date
        ) AS version_group
    FROM marked
), collapsed AS (
    SELECT DISTINCT ON (hash_key_transmission_line, version_group)
        hash_key_transmission_line,
        min(start_date) OVER (
            PARTITION BY hash_key_transmission_line, version_group
        ) AS start_date,
        line_code,
        voltage_level_kv,
        length_km,
        circuit_type,
        origin_substation_name,
        destination_substation_name,
        origin_latitude,
        origin_longitude,
        destination_latitude,
        destination_longitude,
        midpoint_latitude,
        midpoint_longitude,
        status
    FROM grouped
    ORDER BY hash_key_transmission_line, version_group, start_date DESC
), ranged AS (
    SELECT
        versions.*,
        lead(start_date) OVER (
            PARTITION BY hash_key_transmission_line ORDER BY start_date
        ) AS end_date
    FROM collapsed
)
INSERT INTO galaxy.dim_transmission_line (
    hash_key_transmission_line, line_code, voltage_level_kv, length_km,
    circuit_type, origin_substation_name, destination_substation_name,
    origin_latitude, origin_longitude, destination_latitude,
    destination_longitude, midpoint_latitude, midpoint_longitude,
    status, start_date, end_date
)
SELECT
    hash_key_transmission_line, line_code, voltage_level_kv, length_km,
    circuit_type, origin_substation_name, destination_substation_name,
    origin_latitude, origin_longitude, destination_latitude,
    destination_longitude, midpoint_latitude, midpoint_longitude,
    status, start_date, end_date
FROM ranged
ON CONFLICT (hash_key_transmission_line, start_date) DO UPDATE SET
    line_code = EXCLUDED.line_code,
    voltage_level_kv = EXCLUDED.voltage_level_kv,
    length_km = EXCLUDED.length_km,
    circuit_type = EXCLUDED.circuit_type,
    origin_substation_name = EXCLUDED.origin_substation_name,
    destination_substation_name = EXCLUDED.destination_substation_name,
    origin_latitude = EXCLUDED.origin_latitude,
    origin_longitude = EXCLUDED.origin_longitude,
    destination_latitude = EXCLUDED.destination_latitude,
    destination_longitude = EXCLUDED.destination_longitude,
    midpoint_latitude = EXCLUDED.midpoint_latitude,
    midpoint_longitude = EXCLUDED.midpoint_longitude,
    status = EXCLUDED.status,
    end_date = EXCLUDED.end_date
