WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(plant.plant_code, 'UTF8')), 'hex') AS hash_key_power_plant,
        reading.reading_timestamp,
        reading.generation_output_mw,
        reading.available_capacity_mw
    FROM oltp.generation_reading AS reading
    JOIN oltp.plant AS plant ON plant.plant_id = reading.plant_id
), satellite_load AS (
    INSERT INTO data_vault.sat_gen_reading (
        hash_key_power_plant, reading_timestamp, generation_output_mw,
        available_capacity_mw, load_date, record_source
    )
    SELECT
        hash_key_power_plant, reading_timestamp, generation_output_mw,
        available_capacity_mw, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_power_plant, reading_timestamp) DO UPDATE SET
        generation_output_mw = EXCLUDED.generation_output_mw,
        available_capacity_mw = EXCLUDED.available_capacity_mw,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_gen_reading.generation_output_mw IS DISTINCT FROM EXCLUDED.generation_output_mw
       OR sat_gen_reading.available_capacity_mw IS DISTINCT FROM EXCLUDED.available_capacity_mw
    RETURNING 1
)
SELECT count(*) AS rows_processed FROM satellite_load
