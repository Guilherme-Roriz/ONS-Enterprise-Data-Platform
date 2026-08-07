WITH substation_rows AS (
    SELECT
        encode(sha256(convert_to(substation.substation_code, 'UTF8')), 'hex') AS hash_key_substation,
        measurement.reading_timestamp,
        measurement.frequency_hz,
        measurement.voltage_kv,
        measurement.system_load_mw,
        measurement.reliability_index
    FROM oltp.measurement AS measurement
    JOIN oltp.substation AS substation
        ON measurement.asset_type = 'substation'
       AND substation.substation_id = measurement.asset_id
), substation_load AS (
    INSERT INTO data_vault.sat_substation_measurement (
        hash_key_substation, reading_timestamp, frequency_hz, voltage_kv,
        system_load_mw, reliability_index, load_date, record_source
    )
    SELECT
        hash_key_substation, reading_timestamp, frequency_hz, voltage_kv,
        system_load_mw, reliability_index, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM substation_rows
    ON CONFLICT (hash_key_substation, reading_timestamp) DO UPDATE SET
        frequency_hz = EXCLUDED.frequency_hz,
        voltage_kv = EXCLUDED.voltage_kv,
        system_load_mw = EXCLUDED.system_load_mw,
        reliability_index = EXCLUDED.reliability_index,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE ROW(
        sat_substation_measurement.frequency_hz,
        sat_substation_measurement.voltage_kv,
        sat_substation_measurement.system_load_mw,
        sat_substation_measurement.reliability_index
    ) IS DISTINCT FROM ROW(
        EXCLUDED.frequency_hz,
        EXCLUDED.voltage_kv,
        EXCLUDED.system_load_mw,
        EXCLUDED.reliability_index
    )
    RETURNING 1
), line_rows AS (
    SELECT
        encode(sha256(convert_to(line.line_code, 'UTF8')), 'hex') AS hash_key_transmission_line,
        measurement.reading_timestamp,
        measurement.power_flow_mw,
        measurement.losses_mw,
        measurement.frequency_hz,
        measurement.voltage_kv
    FROM oltp.measurement AS measurement
    JOIN oltp.transmission_line AS line
        ON measurement.asset_type = 'transmission_line'
       AND line.line_id = measurement.asset_id
), line_load AS (
    INSERT INTO data_vault.sat_line_measurement (
        hash_key_transmission_line, reading_timestamp, power_flow_mw,
        losses_mw, frequency_hz, voltage_kv, load_date, record_source
    )
    SELECT
        hash_key_transmission_line, reading_timestamp, power_flow_mw,
        losses_mw, frequency_hz, voltage_kv, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM line_rows
    CROSS JOIN (SELECT count(*) FROM substation_load) AS dependency
    ON CONFLICT (hash_key_transmission_line, reading_timestamp) DO UPDATE SET
        power_flow_mw = EXCLUDED.power_flow_mw,
        losses_mw = EXCLUDED.losses_mw,
        frequency_hz = EXCLUDED.frequency_hz,
        voltage_kv = EXCLUDED.voltage_kv,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE ROW(
        sat_line_measurement.power_flow_mw,
        sat_line_measurement.losses_mw,
        sat_line_measurement.frequency_hz,
        sat_line_measurement.voltage_kv
    ) IS DISTINCT FROM ROW(
        EXCLUDED.power_flow_mw,
        EXCLUDED.losses_mw,
        EXCLUDED.frequency_hz,
        EXCLUDED.voltage_kv
    )
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM substation_load)
    + (SELECT count(*) FROM line_load) AS rows_processed
