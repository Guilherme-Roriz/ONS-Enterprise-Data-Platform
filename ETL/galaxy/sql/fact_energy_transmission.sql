WITH source_rows AS (
    SELECT
        reading.*,
        line_dim.sk_transmission_line,
        origin_substation.sk_state
    FROM data_vault.sat_line_measurement AS reading
    JOIN galaxy.dim_transmission_line AS line_dim
        ON line_dim.hash_key_transmission_line = reading.hash_key_transmission_line
       AND line_dim.start_date <= reading.reading_timestamp::date
       AND (line_dim.end_date IS NULL OR reading.reading_timestamp::date < line_dim.end_date)
    LEFT JOIN LATERAL (
        SELECT link.hash_key_substation
        FROM data_vault.link_transmission_line_substation AS link
        WHERE link.hash_key_transmission_line = reading.hash_key_transmission_line
          AND link.role_code = 'ORIGIN'
        ORDER BY link.load_date DESC
        LIMIT 1
    ) AS origin_link ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.sk_state
        FROM galaxy.dim_substation AS dim
        WHERE dim.hash_key_substation = origin_link.hash_key_substation
          AND dim.start_date <= reading.reading_timestamp::date
          AND (dim.end_date IS NULL OR reading.reading_timestamp::date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS origin_substation ON TRUE
)
INSERT INTO galaxy.fact_energy_transmission (
    sk_date, sk_time_of_day, sk_transmission_line, sk_state,
    power_flow_mw, line_loading_pct, losses_mw
)
SELECT
    date_dim.sk_date,
    time_dim.sk_time_of_day,
    source.sk_transmission_line,
    source.sk_state,
    source.power_flow_mw,
    NULL AS line_loading_pct,
    source.losses_mw
FROM source_rows AS source
JOIN galaxy.dim_date AS date_dim
    ON date_dim.full_date = source.reading_timestamp::date
JOIN galaxy.dim_time_of_day AS time_dim
    ON time_dim.sk_time_of_day = EXTRACT(HOUR FROM source.reading_timestamp)::integer * 60
                               + EXTRACT(MINUTE FROM source.reading_timestamp)::integer
ON CONFLICT (sk_date, sk_time_of_day, sk_transmission_line) DO UPDATE SET
    sk_state = EXCLUDED.sk_state,
    power_flow_mw = EXCLUDED.power_flow_mw,
    line_loading_pct = EXCLUDED.line_loading_pct,
    losses_mw = EXCLUDED.losses_mw
