WITH plant_rows AS (
    SELECT
        encode(sha256(convert_to(work_order.order_number, 'UTF8')), 'hex') AS hash_key_work_order,
        encode(sha256(convert_to(plant.plant_code, 'UTF8')), 'hex') AS hash_key_power_plant
    FROM oltp.work_order_asset AS relationship
    JOIN oltp.work_order AS work_order
        ON work_order.work_order_id = relationship.work_order_id
    JOIN oltp.plant AS plant
        ON relationship.asset_type = 'plant'
       AND plant.plant_id = relationship.asset_id
), plant_load AS (
    INSERT INTO data_vault.link_work_order_power_plant (
        hash_key_link_wo_plant, hash_key_work_order, hash_key_power_plant,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(hash_key_work_order, hash_key_power_plant), 'UTF8')), 'hex'),
        hash_key_work_order, hash_key_power_plant, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM plant_rows
    ON CONFLICT (hash_key_link_wo_plant) DO NOTHING
    RETURNING 1
), substation_rows AS (
    SELECT
        encode(sha256(convert_to(work_order.order_number, 'UTF8')), 'hex') AS hash_key_work_order,
        encode(sha256(convert_to(substation.substation_code, 'UTF8')), 'hex') AS hash_key_substation
    FROM oltp.work_order_asset AS relationship
    JOIN oltp.work_order AS work_order
        ON work_order.work_order_id = relationship.work_order_id
    JOIN oltp.substation AS substation
        ON relationship.asset_type = 'substation'
       AND substation.substation_id = relationship.asset_id
), substation_load AS (
    INSERT INTO data_vault.link_work_order_substation (
        hash_key_link_wo_sub, hash_key_work_order, hash_key_substation,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(hash_key_work_order, hash_key_substation), 'UTF8')), 'hex'),
        hash_key_work_order, hash_key_substation, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM substation_rows
    CROSS JOIN (SELECT count(*) FROM plant_load) AS dependency
    ON CONFLICT (hash_key_link_wo_sub) DO NOTHING
    RETURNING 1
), line_rows AS (
    SELECT
        encode(sha256(convert_to(work_order.order_number, 'UTF8')), 'hex') AS hash_key_work_order,
        encode(sha256(convert_to(line.line_code, 'UTF8')), 'hex') AS hash_key_transmission_line
    FROM oltp.work_order_asset AS relationship
    JOIN oltp.work_order AS work_order
        ON work_order.work_order_id = relationship.work_order_id
    JOIN oltp.transmission_line AS line
        ON relationship.asset_type = 'transmission_line'
       AND line.line_id = relationship.asset_id
), line_load AS (
    INSERT INTO data_vault.link_work_order_transmission_line (
        hash_key_link_wo_line, hash_key_work_order, hash_key_transmission_line,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(hash_key_work_order, hash_key_transmission_line), 'UTF8')), 'hex'),
        hash_key_work_order, hash_key_transmission_line, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM line_rows
    CROSS JOIN (SELECT count(*) FROM substation_load) AS dependency
    ON CONFLICT (hash_key_link_wo_line) DO NOTHING
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM plant_load)
    + (SELECT count(*) FROM substation_load)
    + (SELECT count(*) FROM line_load) AS rows_processed
