WITH minutes AS (
    SELECT minute_of_day, minute_of_day / 60 AS hour, minute_of_day % 60 AS minute
    FROM generate_series(0, 1439) AS series(minute_of_day)
)
INSERT INTO galaxy.dim_time_of_day (
    sk_time_of_day, hour, minute, hh_mm, period_of_day, shift,
    peak_period, off_peak_period
)
SELECT
    minute_of_day,
    hour,
    minute,
    lpad(hour::text, 2, '0') || ':' || lpad(minute::text, 2, '0'),
    CASE
        WHEN hour < 6 THEN 'Dawn'
        WHEN hour < 12 THEN 'Morning'
        WHEN hour < 18 THEN 'Afternoon'
        ELSE 'Night'
    END,
    CASE
        WHEN hour >= 6 AND hour < 14 THEN 'Day Shift'
        WHEN hour >= 14 AND hour < 22 THEN 'Evening'
        ELSE 'Night'
    END,
    hour >= 18 AND hour < 21,
    NOT (hour >= 18 AND hour < 21)
FROM minutes
ON CONFLICT (sk_time_of_day) DO UPDATE SET
    hour = EXCLUDED.hour,
    minute = EXCLUDED.minute,
    hh_mm = EXCLUDED.hh_mm,
    period_of_day = EXCLUDED.period_of_day,
    shift = EXCLUDED.shift,
    peak_period = EXCLUDED.peak_period,
    off_peak_period = EXCLUDED.off_peak_period
