WITH source_rows AS (
    SELECT
        encode(sha256(convert_to(work_order.order_number, 'UTF8')), 'hex') AS hash_key_work_order,
        encode(sha256(convert_to(maintenance_type.type_code, 'UTF8')), 'hex') AS hash_key_maintenance_type,
        work_order.order_number,
        work_order.scheduled_date,
        work_order.planned_duration_hours,
        work_order.actual_duration_hours,
        work_order.cost,
        work_order.overdue_flag,
        work_order.asset_availability_pct,
        work_order.last_updated::date AS effective_date,
        encode(sha256(convert_to(concat_ws('|',
            maintenance_type.type_code,
            COALESCE(work_order.scheduled_date::text, '∅'),
            COALESCE(work_order.planned_duration_hours::text, '∅'),
            COALESCE(work_order.actual_duration_hours::text, '∅'),
            COALESCE(work_order.cost::text, '∅'),
            work_order.overdue_flag::text,
            COALESCE(work_order.asset_availability_pct::text, '∅')
        ), 'UTF8')), 'hex') AS hash_diff
    FROM oltp.work_order AS work_order
    JOIN oltp.maintenance_type AS maintenance_type
        ON maintenance_type.maintenance_type_id = work_order.maintenance_type_id
), hub_load AS (
    INSERT INTO data_vault.hub_work_order (
        hash_key_work_order, order_number, load_date, record_source
    )
    SELECT hash_key_work_order, order_number, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows
    ON CONFLICT (hash_key_work_order) DO NOTHING
    RETURNING 1
), satellite_close AS (
    UPDATE data_vault.sat_work_order_detail AS target
    SET end_date = source.effective_date
    FROM source_rows AS source
    WHERE target.hash_key_work_order = source.hash_key_work_order
      AND target.end_date IS NULL
      AND target.start_date < source.effective_date
      AND target.hash_diff IS DISTINCT FROM source.hash_diff
    RETURNING 1
), satellite_load AS (
    INSERT INTO data_vault.sat_work_order_detail (
        hash_key_work_order, start_date, end_date, hash_key_maintenance_type,
        scheduled_date, planned_duration_hours, actual_duration_hours, cost,
        overdue_flag, asset_availability_pct, hash_diff, load_date, record_source
    )
    SELECT
        source.hash_key_work_order, source.effective_date, NULL,
        source.hash_key_maintenance_type, source.scheduled_date,
        source.planned_duration_hours, source.actual_duration_hours, source.cost,
        source.overdue_flag, source.asset_availability_pct, source.hash_diff,
        CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM source_rows AS source
    CROSS JOIN (SELECT count(*) FROM hub_load) AS hub_dependency
    CROSS JOIN (SELECT count(*) FROM satellite_close) AS close_dependency
    WHERE NOT EXISTS (
        SELECT 1 FROM data_vault.sat_work_order_detail AS current_row
        WHERE current_row.hash_key_work_order = source.hash_key_work_order
          AND current_row.end_date IS NULL
          AND current_row.hash_diff = source.hash_diff
    )
    ON CONFLICT (hash_key_work_order, start_date) DO UPDATE SET
        end_date = NULL,
        hash_key_maintenance_type = EXCLUDED.hash_key_maintenance_type,
        scheduled_date = EXCLUDED.scheduled_date,
        planned_duration_hours = EXCLUDED.planned_duration_hours,
        actual_duration_hours = EXCLUDED.actual_duration_hours,
        cost = EXCLUDED.cost,
        overdue_flag = EXCLUDED.overdue_flag,
        asset_availability_pct = EXCLUDED.asset_availability_pct,
        hash_diff = EXCLUDED.hash_diff,
        load_date = EXCLUDED.load_date,
        record_source = EXCLUDED.record_source
    WHERE sat_work_order_detail.hash_diff IS DISTINCT FROM EXCLUDED.hash_diff
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM hub_load)
    + (SELECT count(*) FROM satellite_close)
    + (SELECT count(*) FROM satellite_load) AS rows_processed
