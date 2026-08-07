WITH vault_dates AS (
    SELECT reading_timestamp::date AS full_date FROM data_vault.sat_gen_reading
    UNION ALL SELECT reading_timestamp::date FROM data_vault.sat_substation_measurement
    UNION ALL SELECT reading_timestamp::date FROM data_vault.sat_line_measurement
    UNION ALL SELECT start_datetime::date FROM data_vault.sat_occurrence_detail
    UNION ALL SELECT scheduled_date FROM data_vault.sat_work_order_detail
    UNION ALL SELECT snapshot_date FROM data_vault.sat_power_plant_daily_snapshot
    UNION ALL SELECT snapshot_date FROM data_vault.sat_substation_daily_snapshot
    UNION ALL SELECT snapshot_date FROM data_vault.sat_line_daily_snapshot
), bounds AS (
    SELECT
        LEAST(CAST(:start_date AS date), COALESCE(MIN(full_date), CAST(:start_date AS date))) AS first_date,
        GREATEST(CAST(:end_date AS date), COALESCE(MAX(full_date), CAST(:end_date AS date))) AS last_date
    FROM vault_dates
), dates AS (
    SELECT CAST(day_value AS date) AS full_date
    FROM bounds
    CROSS JOIN LATERAL generate_series(first_date, last_date, INTERVAL '1 day') AS series(day_value)
)
INSERT INTO galaxy.dim_date (
    sk_date, full_date, year, quarter, quarter_name, month, month_name,
    week_number, day, day_of_year, day_of_week, is_weekend, semester,
    holiday_flag, month_start_flag, month_end_flag
)
SELECT
    CAST(to_char(full_date, 'YYYYMMDD') AS integer),
    full_date,
    EXTRACT(YEAR FROM full_date)::integer,
    EXTRACT(QUARTER FROM full_date)::integer,
    'Q' || EXTRACT(QUARTER FROM full_date)::integer || ' ' || EXTRACT(YEAR FROM full_date)::integer,
    EXTRACT(MONTH FROM full_date)::integer,
    trim(to_char(full_date, 'Month')),
    CAST(to_char(full_date, 'IW') AS integer),
    EXTRACT(DAY FROM full_date)::integer,
    EXTRACT(DOY FROM full_date)::integer,
    trim(to_char(full_date, 'Day')),
    EXTRACT(ISODOW FROM full_date) IN (6, 7),
    CASE WHEN EXTRACT(MONTH FROM full_date) <= 6 THEN 1 ELSE 2 END,
    FALSE,
    full_date = date_trunc('month', full_date)::date,
    full_date = (date_trunc('month', full_date) + INTERVAL '1 month - 1 day')::date
FROM dates
ON CONFLICT (sk_date) DO UPDATE SET
    full_date = EXCLUDED.full_date,
    year = EXCLUDED.year,
    quarter = EXCLUDED.quarter,
    quarter_name = EXCLUDED.quarter_name,
    month = EXCLUDED.month,
    month_name = EXCLUDED.month_name,
    week_number = EXCLUDED.week_number,
    day = EXCLUDED.day,
    day_of_year = EXCLUDED.day_of_year,
    day_of_week = EXCLUDED.day_of_week,
    is_weekend = EXCLUDED.is_weekend,
    semester = EXCLUDED.semester,
    month_start_flag = EXCLUDED.month_start_flag,
    month_end_flag = EXCLUDED.month_end_flag
