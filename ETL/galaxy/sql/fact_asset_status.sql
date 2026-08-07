WITH assets AS (
    SELECT
        snapshot.snapshot_date,
        plant.sk_power_plant,
        NULL::integer AS sk_substation,
        NULL::integer AS sk_transmission_line,
        plant.sk_state,
        snapshot.availability_pct,
        snapshot.in_operation_flag,
        ROUND(
            (snapshot.snapshot_date - plant.commissioning_date) / 365.2425,
            2
        ) AS asset_age_years
    FROM data_vault.sat_power_plant_daily_snapshot AS snapshot
    JOIN galaxy.dim_power_plant AS plant
        ON plant.hash_key_power_plant = snapshot.hash_key_power_plant
       AND plant.start_date <= snapshot.snapshot_date
       AND (plant.end_date IS NULL OR snapshot.snapshot_date < plant.end_date)

    UNION ALL

    SELECT
        snapshot.snapshot_date,
        NULL::integer AS sk_power_plant,
        substation.sk_substation,
        NULL::integer AS sk_transmission_line,
        substation.sk_state,
        snapshot.availability_pct,
        snapshot.in_operation_flag,
        NULL::numeric AS asset_age_years
    FROM data_vault.sat_substation_daily_snapshot AS snapshot
    JOIN galaxy.dim_substation AS substation
        ON substation.hash_key_substation = snapshot.hash_key_substation
       AND substation.start_date <= snapshot.snapshot_date
       AND (substation.end_date IS NULL OR snapshot.snapshot_date < substation.end_date)

    UNION ALL

    SELECT
        snapshot.snapshot_date,
        NULL::integer AS sk_power_plant,
        NULL::integer AS sk_substation,
        line.sk_transmission_line,
        origin_substation.sk_state,
        snapshot.availability_pct,
        snapshot.in_operation_flag,
        NULL::numeric AS asset_age_years
    FROM data_vault.sat_line_daily_snapshot AS snapshot
    JOIN galaxy.dim_transmission_line AS line
        ON line.hash_key_transmission_line = snapshot.hash_key_transmission_line
       AND line.start_date <= snapshot.snapshot_date
       AND (line.end_date IS NULL OR snapshot.snapshot_date < line.end_date)
    LEFT JOIN LATERAL (
        SELECT link.hash_key_substation
        FROM data_vault.link_transmission_line_substation AS link
        WHERE link.hash_key_transmission_line = snapshot.hash_key_transmission_line
          AND link.role_code = 'ORIGIN'
        ORDER BY link.load_date DESC
        LIMIT 1
    ) AS origin_link ON TRUE
    LEFT JOIN LATERAL (
        SELECT dim.sk_state
        FROM galaxy.dim_substation AS dim
        WHERE dim.hash_key_substation = origin_link.hash_key_substation
          AND dim.start_date <= snapshot.snapshot_date
          AND (dim.end_date IS NULL OR snapshot.snapshot_date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS origin_substation ON TRUE
), source_rows AS (
    SELECT
        date_dim.sk_date,
        assets.sk_power_plant,
        assets.sk_substation,
        assets.sk_transmission_line,
        assets.sk_state,
        junk.sk_junk_flags,
        assets.availability_pct,
        assets.asset_age_years
    FROM assets
    JOIN galaxy.dim_date AS date_dim ON date_dim.full_date = assets.snapshot_date
    JOIN galaxy.dim_junk_flags AS junk
        ON junk.resolved_flag = 'N/A'
       AND junk.overdue_flag = 'N/A'
       AND junk.in_operation_flag = CASE WHEN assets.in_operation_flag THEN 'Y' ELSE 'N' END
)
INSERT INTO galaxy.fact_asset_status (
    sk_date, sk_power_plant, sk_substation, sk_transmission_line,
    sk_state, sk_junk_flags, availability_pct, asset_age_years
)
SELECT
    sk_date, sk_power_plant, sk_substation, sk_transmission_line,
    sk_state, sk_junk_flags, availability_pct, asset_age_years
FROM source_rows
ON CONFLICT (
    sk_date,
    (COALESCE(sk_power_plant, -1)),
    (COALESCE(sk_substation, -1)),
    (COALESCE(sk_transmission_line, -1))
) DO UPDATE SET
    sk_state = EXCLUDED.sk_state,
    sk_junk_flags = EXCLUDED.sk_junk_flags,
    availability_pct = EXCLUDED.availability_pct,
    asset_age_years = EXCLUDED.asset_age_years
