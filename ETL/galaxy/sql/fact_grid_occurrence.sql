WITH latest_detail AS (
    SELECT DISTINCT ON (detail.hash_key_occurrence)
        detail.*
    FROM data_vault.sat_occurrence_detail AS detail
    ORDER BY detail.hash_key_occurrence, detail.start_date DESC
), occurrence_base AS (
    SELECT
        hub.ticket_number,
        detail.*
    FROM latest_detail AS detail
    JOIN data_vault.hub_occurrence AS hub USING (hash_key_occurrence)
), assets AS (
    SELECT
        occurrence.*,
        plant.sk_power_plant,
        NULL::integer AS sk_substation,
        NULL::integer AS sk_transmission_line,
        plant.sk_state
    FROM occurrence_base AS occurrence
    JOIN data_vault.link_occurrence_power_plant AS link
        USING (hash_key_occurrence)
    JOIN galaxy.dim_power_plant AS plant
        ON plant.hash_key_power_plant = link.hash_key_power_plant
       AND plant.start_date <= occurrence.start_datetime::date
       AND (plant.end_date IS NULL OR occurrence.start_datetime::date < plant.end_date)

    UNION ALL

    SELECT
        occurrence.*,
        NULL::integer AS sk_power_plant,
        substation.sk_substation,
        NULL::integer AS sk_transmission_line,
        substation.sk_state
    FROM occurrence_base AS occurrence
    JOIN data_vault.link_occurrence_substation AS link
        USING (hash_key_occurrence)
    JOIN galaxy.dim_substation AS substation
        ON substation.hash_key_substation = link.hash_key_substation
       AND substation.start_date <= occurrence.start_datetime::date
       AND (substation.end_date IS NULL OR occurrence.start_datetime::date < substation.end_date)

    UNION ALL

    SELECT
        occurrence.*,
        NULL::integer AS sk_power_plant,
        NULL::integer AS sk_substation,
        line.sk_transmission_line,
        origin_substation.sk_state
    FROM occurrence_base AS occurrence
    JOIN data_vault.link_occurrence_transmission_line AS link
        USING (hash_key_occurrence)
    JOIN galaxy.dim_transmission_line AS line
        ON line.hash_key_transmission_line = link.hash_key_transmission_line
       AND line.start_date <= occurrence.start_datetime::date
       AND (line.end_date IS NULL OR occurrence.start_datetime::date < line.end_date)
    LEFT JOIN LATERAL (
        SELECT line_link.hash_key_substation
        FROM data_vault.link_transmission_line_substation AS line_link
        WHERE line_link.hash_key_transmission_line = link.hash_key_transmission_line
          AND line_link.role_code = 'ORIGIN'
        ORDER BY line_link.load_date DESC
        LIMIT 1
    ) AS origin_link ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.sk_state
        FROM galaxy.dim_substation AS dim
        WHERE dim.hash_key_substation = origin_link.hash_key_substation
          AND dim.start_date <= occurrence.start_datetime::date
          AND (dim.end_date IS NULL OR occurrence.start_datetime::date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS origin_substation ON TRUE
), source_rows AS (
    SELECT
        assets.ticket_number AS occurrence_id,
        date_dim.sk_date,
        time_dim.sk_time_of_day,
        assets.sk_power_plant,
        assets.sk_substation,
        assets.sk_transmission_line,
        assets.sk_state,
        occurrence_type.sk_occurrence_type,
        junk.sk_junk_flags,
        assets.duration_minutes,
        assets.affected_load_mw,
        assets.customers_affected
    FROM assets
    JOIN galaxy.dim_date AS date_dim
        ON date_dim.full_date = assets.start_datetime::date
    JOIN galaxy.dim_time_of_day AS time_dim
        ON time_dim.sk_time_of_day = EXTRACT(HOUR FROM assets.start_datetime)::integer * 60
                                   + EXTRACT(MINUTE FROM assets.start_datetime)::integer
    JOIN galaxy.dim_occurrence_type AS occurrence_type
        ON occurrence_type.hash_key_occurrence_type = assets.hash_key_occurrence_type
    JOIN galaxy.dim_junk_flags AS junk
        ON junk.resolved_flag = CASE WHEN assets.resolved_flag THEN 'Y' ELSE 'N' END
       AND junk.overdue_flag = 'N/A'
       AND junk.in_operation_flag = 'N/A'
)
INSERT INTO galaxy.fact_grid_occurrence (
    occurrence_id, sk_date, sk_time_of_day, sk_power_plant, sk_substation,
    sk_transmission_line, sk_state, sk_occurrence_type, sk_junk_flags,
    duration_minutes, affected_load_mw, customers_affected
)
SELECT
    occurrence_id, sk_date, sk_time_of_day, sk_power_plant, sk_substation,
    sk_transmission_line, sk_state, sk_occurrence_type, sk_junk_flags,
    duration_minutes, affected_load_mw, customers_affected
FROM source_rows
ON CONFLICT (
    occurrence_id,
    (COALESCE(sk_power_plant, -1)),
    (COALESCE(sk_substation, -1)),
    (COALESCE(sk_transmission_line, -1))
) DO UPDATE SET
    sk_date = EXCLUDED.sk_date,
    sk_time_of_day = EXCLUDED.sk_time_of_day,
    sk_state = EXCLUDED.sk_state,
    sk_occurrence_type = EXCLUDED.sk_occurrence_type,
    sk_junk_flags = EXCLUDED.sk_junk_flags,
    duration_minutes = EXCLUDED.duration_minutes,
    affected_load_mw = EXCLUDED.affected_load_mw,
    customers_affected = EXCLUDED.customers_affected
