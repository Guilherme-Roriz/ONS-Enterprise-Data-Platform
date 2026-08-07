INSERT INTO galaxy.fact_energy_generation (
    sk_date, sk_time_of_day, sk_power_plant, sk_state,
    generation_output_mw, available_capacity_mw, capacity_factor_pct
)
SELECT
    date_dim.sk_date,
    time_dim.sk_time_of_day,
    plant_dim.sk_power_plant,
    plant_dim.sk_state,
    reading.generation_output_mw,
    reading.available_capacity_mw,
    ROUND(
        reading.generation_output_mw / NULLIF(plant_dim.installed_capacity_mw, 0) * 100,
        4
    ) AS capacity_factor_pct
FROM data_vault.sat_gen_reading AS reading
JOIN galaxy.dim_date AS date_dim
    ON date_dim.full_date = reading.reading_timestamp::date
JOIN galaxy.dim_time_of_day AS time_dim
    ON time_dim.sk_time_of_day = EXTRACT(HOUR FROM reading.reading_timestamp)::integer * 60
                               + EXTRACT(MINUTE FROM reading.reading_timestamp)::integer
JOIN galaxy.dim_power_plant AS plant_dim
    ON plant_dim.hash_key_power_plant = reading.hash_key_power_plant
   AND plant_dim.start_date <= reading.reading_timestamp::date
   AND (plant_dim.end_date IS NULL OR reading.reading_timestamp::date < plant_dim.end_date)
ON CONFLICT (sk_date, sk_time_of_day, sk_power_plant) DO UPDATE SET
    sk_state = EXCLUDED.sk_state,
    generation_output_mw = EXCLUDED.generation_output_mw,
    available_capacity_mw = EXCLUDED.available_capacity_mw,
    capacity_factor_pct = EXCLUDED.capacity_factor_pct
