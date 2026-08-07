WITH boundaries AS (
    SELECT hash_key_substation, start_date
    FROM data_vault.sat_substation_attributes
    UNION
    SELECT hash_key_substation, start_date
    FROM data_vault.sat_substation_status
), versions AS (
    SELECT
        boundary.hash_key_substation,
        boundary.start_date,
        attributes.substation_name,
        attributes.voltage_level_kv,
        attributes.substation_type,
        status.status,
        state.state_name,
        state.sk_state
    FROM boundaries AS boundary
    LEFT JOIN LATERAL (
        SELECT sat.*
        FROM data_vault.sat_substation_attributes AS sat
        WHERE sat.hash_key_substation = boundary.hash_key_substation
          AND sat.start_date <= boundary.start_date
          AND (sat.end_date IS NULL OR boundary.start_date < sat.end_date)
        ORDER BY sat.start_date DESC
        LIMIT 1
    ) AS attributes ON TRUE
    LEFT JOIN LATERAL (
        SELECT sat.status
        FROM data_vault.sat_substation_status AS sat
        WHERE sat.hash_key_substation = boundary.hash_key_substation
          AND sat.start_date <= boundary.start_date
          AND (sat.end_date IS NULL OR boundary.start_date < sat.end_date)
        ORDER BY sat.start_date DESC
        LIMIT 1
    ) AS status ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.state_name, dim.sk_state
        FROM data_vault.link_substation_state AS link
        JOIN galaxy.dim_state AS dim ON dim.hash_key_state = link.hash_key_state
        WHERE link.hash_key_substation = boundary.hash_key_substation
        ORDER BY link.load_date DESC
        LIMIT 1
    ) AS state ON TRUE
), marked AS (
    SELECT
        versions.*,
        CASE
            WHEN row_number() OVER (
                PARTITION BY hash_key_substation ORDER BY start_date
            ) = 1 THEN 1
            WHEN ROW(voltage_level_kv, status)
                 IS DISTINCT FROM lag(ROW(voltage_level_kv, status)) OVER (
                     PARTITION BY hash_key_substation ORDER BY start_date
                 ) THEN 1
            ELSE 0
        END AS is_new_version
    FROM versions
), grouped AS (
    SELECT
        marked.*,
        sum(is_new_version) OVER (
            PARTITION BY hash_key_substation ORDER BY start_date
        ) AS version_group
    FROM marked
), collapsed AS (
    SELECT DISTINCT ON (hash_key_substation, version_group)
        hash_key_substation,
        min(start_date) OVER (
            PARTITION BY hash_key_substation, version_group
        ) AS start_date,
        substation_name,
        voltage_level_kv,
        substation_type,
        status,
        state_name,
        sk_state
    FROM grouped
    ORDER BY hash_key_substation, version_group, start_date DESC
), ranged AS (
    SELECT
        versions.*,
        lead(start_date) OVER (
            PARTITION BY hash_key_substation ORDER BY start_date
        ) AS end_date
    FROM collapsed
)
INSERT INTO galaxy.dim_substation (
    hash_key_substation, substation_name, voltage_level_kv,
    substation_type, state_name, status, start_date, end_date, sk_state
)
SELECT
    hash_key_substation, substation_name, voltage_level_kv,
    substation_type, state_name, status, start_date, end_date, sk_state
FROM ranged
ON CONFLICT (hash_key_substation, start_date) DO UPDATE SET
    substation_name = EXCLUDED.substation_name,
    voltage_level_kv = EXCLUDED.voltage_level_kv,
    substation_type = EXCLUDED.substation_type,
    state_name = EXCLUDED.state_name,
    status = EXCLUDED.status,
    end_date = EXCLUDED.end_date,
    sk_state = EXCLUDED.sk_state
