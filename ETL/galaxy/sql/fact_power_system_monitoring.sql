WITH monitoring AS (
    SELECT
        measurement.reading_timestamp,
        substation.sk_substation,
        NULL::integer AS sk_transmission_line,
        substation.sk_state,
        measurement.frequency_hz,
        measurement.voltage_kv,
        measurement.reliability_index,
        measurement.system_load_mw
    FROM data_vault.sat_substation_measurement AS measurement
    JOIN galaxy.dim_substation AS substation
        ON substation.hash_key_substation = measurement.hash_key_substation
       AND substation.start_date <= measurement.reading_timestamp::date
       AND (substation.end_date IS NULL OR measurement.reading_timestamp::date < substation.end_date)

    UNION ALL

    SELECT
        measurement.reading_timestamp,
        NULL::integer AS sk_substation,
        line.sk_transmission_line,
        origin_substation.sk_state,
        measurement.frequency_hz,
        measurement.voltage_kv,
        NULL::numeric AS reliability_index,
        NULL::numeric AS system_load_mw
    FROM data_vault.sat_line_measurement AS measurement
    JOIN galaxy.dim_transmission_line AS line
        ON line.hash_key_transmission_line = measurement.hash_key_transmission_line
       AND line.start_date <= measurement.reading_timestamp::date
       AND (line.end_date IS NULL OR measurement.reading_timestamp::date < line.end_date)
    LEFT JOIN LATERAL (
        SELECT link.hash_key_substation
        FROM data_vault.link_transmission_line_substation AS link
        WHERE link.hash_key_transmission_line = measurement.hash_key_transmission_line
          AND link.role_code = 'ORIGIN'
        ORDER BY link.load_date DESC
        LIMIT 1
    ) AS origin_link ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.sk_state
        FROM galaxy.dim_substation AS dim
        WHERE dim.hash_key_substation = origin_link.hash_key_substation
          AND dim.start_date <= measurement.reading_timestamp::date
          AND (dim.end_date IS NULL OR measurement.reading_timestamp::date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS origin_substation ON TRUE
), source_rows AS (
    SELECT
        date_dim.sk_date,
        time_dim.sk_time_of_day,
        monitoring.sk_substation,
        monitoring.sk_transmission_line,
        monitoring.sk_state,
        monitoring.frequency_hz,
        monitoring.voltage_kv,
        monitoring.reliability_index,
        monitoring.system_load_mw
    FROM monitoring
    JOIN galaxy.dim_date AS date_dim
        ON date_dim.full_date = monitoring.reading_timestamp::date
    JOIN galaxy.dim_time_of_day AS time_dim
        ON time_dim.sk_time_of_day = EXTRACT(HOUR FROM monitoring.reading_timestamp)::integer * 60
                                   + EXTRACT(MINUTE FROM monitoring.reading_timestamp)::integer
)
INSERT INTO galaxy.fact_power_system_monitoring (
    sk_date, sk_time_of_day, sk_substation, sk_transmission_line,
    sk_state, frequency_hz, voltage_kv, reliability_index, system_load_mw
)
SELECT
    sk_date, sk_time_of_day, sk_substation, sk_transmission_line,
    sk_state, frequency_hz, voltage_kv, reliability_index, system_load_mw
FROM source_rows
ON CONFLICT (
    sk_date,
    sk_time_of_day,
    (COALESCE(sk_substation, -1)),
    (COALESCE(sk_transmission_line, -1))
) DO UPDATE SET
    sk_state = EXCLUDED.sk_state,
    frequency_hz = EXCLUDED.frequency_hz,
    voltage_kv = EXCLUDED.voltage_kv,
    reliability_index = EXCLUDED.reliability_index,
    system_load_mw = EXCLUDED.system_load_mw
