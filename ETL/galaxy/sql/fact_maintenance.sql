WITH latest_detail AS (
    SELECT DISTINCT ON (detail.hash_key_work_order)
        detail.*
    FROM data_vault.sat_work_order_detail AS detail
    ORDER BY detail.hash_key_work_order, detail.start_date DESC
), work_order_base AS (
    SELECT
        hub.order_number,
        detail.*
    FROM latest_detail AS detail
    JOIN data_vault.hub_work_order AS hub USING (hash_key_work_order)
    WHERE detail.scheduled_date IS NOT NULL
), assets AS (
    SELECT
        work_order.*,
        plant.sk_power_plant,
        NULL::integer AS sk_substation,
        NULL::integer AS sk_transmission_line,
        plant.sk_state
    FROM work_order_base AS work_order
    JOIN data_vault.link_work_order_power_plant AS link USING (hash_key_work_order)
    JOIN galaxy.dim_power_plant AS plant
        ON plant.hash_key_power_plant = link.hash_key_power_plant
       AND plant.start_date <= work_order.scheduled_date
       AND (plant.end_date IS NULL OR work_order.scheduled_date < plant.end_date)

    UNION ALL

    SELECT
        work_order.*,
        NULL::integer AS sk_power_plant,
        substation.sk_substation,
        NULL::integer AS sk_transmission_line,
        substation.sk_state
    FROM work_order_base AS work_order
    JOIN data_vault.link_work_order_substation AS link USING (hash_key_work_order)
    JOIN galaxy.dim_substation AS substation
        ON substation.hash_key_substation = link.hash_key_substation
       AND substation.start_date <= work_order.scheduled_date
       AND (substation.end_date IS NULL OR work_order.scheduled_date < substation.end_date)

    UNION ALL

    SELECT
        work_order.*,
        NULL::integer AS sk_power_plant,
        NULL::integer AS sk_substation,
        line.sk_transmission_line,
        origin_substation.sk_state
    FROM work_order_base AS work_order
    JOIN data_vault.link_work_order_transmission_line AS link USING (hash_key_work_order)
    JOIN galaxy.dim_transmission_line AS line
        ON line.hash_key_transmission_line = link.hash_key_transmission_line
       AND line.start_date <= work_order.scheduled_date
       AND (line.end_date IS NULL OR work_order.scheduled_date < line.end_date)
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
          AND dim.start_date <= work_order.scheduled_date
          AND (dim.end_date IS NULL OR work_order.scheduled_date < dim.end_date)
        ORDER BY dim.start_date DESC
        LIMIT 1
    ) AS origin_substation ON TRUE
), source_rows AS (
    SELECT
        assets.order_number AS work_order_number,
        date_dim.sk_date,
        assets.sk_power_plant,
        assets.sk_substation,
        assets.sk_transmission_line,
        assets.sk_state,
        maintenance_type.sk_maintenance_type,
        junk.sk_junk_flags,
        assets.planned_duration_hours,
        assets.actual_duration_hours,
        assets.cost,
        assets.asset_availability_pct
    FROM assets
    JOIN galaxy.dim_date AS date_dim ON date_dim.full_date = assets.scheduled_date
    JOIN galaxy.dim_maintenance_type AS maintenance_type
        ON maintenance_type.hash_key_maintenance_type = assets.hash_key_maintenance_type
    JOIN galaxy.dim_junk_flags AS junk
        ON junk.resolved_flag = 'N/A'
       AND junk.overdue_flag = CASE WHEN assets.overdue_flag THEN 'Y' ELSE 'N' END
       AND junk.in_operation_flag = 'N/A'
)
INSERT INTO galaxy.fact_maintenance (
    work_order_number, sk_date, sk_power_plant, sk_substation,
    sk_transmission_line, sk_state, sk_maintenance_type, sk_junk_flags,
    planned_duration_hours, actual_duration_hours, cost, asset_availability_pct
)
SELECT
    work_order_number, sk_date, sk_power_plant, sk_substation,
    sk_transmission_line, sk_state, sk_maintenance_type, sk_junk_flags,
    planned_duration_hours, actual_duration_hours, cost, asset_availability_pct
FROM source_rows
ON CONFLICT (
    work_order_number,
    (COALESCE(sk_power_plant, -1)),
    (COALESCE(sk_substation, -1)),
    (COALESCE(sk_transmission_line, -1))
) DO UPDATE SET
    sk_date = EXCLUDED.sk_date,
    sk_state = EXCLUDED.sk_state,
    sk_maintenance_type = EXCLUDED.sk_maintenance_type,
    sk_junk_flags = EXCLUDED.sk_junk_flags,
    planned_duration_hours = EXCLUDED.planned_duration_hours,
    actual_duration_hours = EXCLUDED.actual_duration_hours,
    cost = EXCLUDED.cost,
    asset_availability_pct = EXCLUDED.asset_availability_pct
