WITH plant_rows AS (
    SELECT
        encode(sha256(convert_to(plant.plant_code, 'UTF8')), 'hex') AS hash_key_power_plant,
        status.snapshot_date,
        status.availability_pct,
        status.in_operation_flag
    FROM oltp.asset_status AS status
    JOIN oltp.plant AS plant
        ON status.asset_type = 'plant'
       AND plant.plant_id = status.asset_id
), plant_load AS (
    INSERT INTO data_vault.sat_power_plant_daily_snapshot (
        hash_key_power_plant, snapshot_date, availability_pct,
        in_operation_flag, load_date, record_source
    )
    SELECT
        hash_key_power_plant, snapshot_date, availability_pct,
        in_operation_flag, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM plant_rows
    ON CONFLICT (hash_key_power_plant, snapshot_date) DO UPDATE SET
        availability_pct = EXCLUDED.availability_pct,
        in_operation_flag = EXCLUDED.in_operation_flag,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE ROW(
        sat_power_plant_daily_snapshot.availability_pct,
        sat_power_plant_daily_snapshot.in_operation_flag
    ) IS DISTINCT FROM ROW(EXCLUDED.availability_pct, EXCLUDED.in_operation_flag)
    RETURNING 1
), substation_rows AS (
    SELECT
        encode(sha256(convert_to(substation.substation_code, 'UTF8')), 'hex') AS hash_key_substation,
        status.snapshot_date,
        status.availability_pct,
        status.in_operation_flag
    FROM oltp.asset_status AS status
    JOIN oltp.substation AS substation
        ON status.asset_type = 'substation'
       AND substation.substation_id = status.asset_id
), substation_load AS (
    INSERT INTO data_vault.sat_substation_daily_snapshot (
        hash_key_substation, snapshot_date, availability_pct,
        in_operation_flag, load_date, record_source
    )
    SELECT
        hash_key_substation, snapshot_date, availability_pct,
        in_operation_flag, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM substation_rows
    CROSS JOIN (SELECT count(*) FROM plant_load) AS dependency
    ON CONFLICT (hash_key_substation, snapshot_date) DO UPDATE SET
        availability_pct = EXCLUDED.availability_pct,
        in_operation_flag = EXCLUDED.in_operation_flag,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE ROW(
        sat_substation_daily_snapshot.availability_pct,
        sat_substation_daily_snapshot.in_operation_flag
    ) IS DISTINCT FROM ROW(EXCLUDED.availability_pct, EXCLUDED.in_operation_flag)
    RETURNING 1
), line_rows AS (
    SELECT
        encode(sha256(convert_to(line.line_code, 'UTF8')), 'hex') AS hash_key_transmission_line,
        status.snapshot_date,
        status.availability_pct,
        status.in_operation_flag
    FROM oltp.asset_status AS status
    JOIN oltp.transmission_line AS line
        ON status.asset_type = 'transmission_line'
       AND line.line_id = status.asset_id
), line_load AS (
    INSERT INTO data_vault.sat_line_daily_snapshot (
        hash_key_transmission_line, snapshot_date, availability_pct,
        in_operation_flag, load_date, record_source
    )
    SELECT
        hash_key_transmission_line, snapshot_date, availability_pct,
        in_operation_flag, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM line_rows
    CROSS JOIN (SELECT count(*) FROM substation_load) AS dependency
    ON CONFLICT (hash_key_transmission_line, snapshot_date) DO UPDATE SET
        availability_pct = EXCLUDED.availability_pct,
        in_operation_flag = EXCLUDED.in_operation_flag,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE ROW(
        sat_line_daily_snapshot.availability_pct,
        sat_line_daily_snapshot.in_operation_flag
    ) IS DISTINCT FROM ROW(EXCLUDED.availability_pct, EXCLUDED.in_operation_flag)
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM plant_load)
    + (SELECT count(*) FROM substation_load)
    + (SELECT count(*) FROM line_load) AS rows_processed
