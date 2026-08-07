WITH plant_rows AS (
    SELECT
        encode(sha256(convert_to(occurrence.ticket_number, 'UTF8')), 'hex') AS hash_key_occurrence,
        encode(sha256(convert_to(plant.plant_code, 'UTF8')), 'hex') AS hash_key_power_plant
    FROM oltp.occurrence_asset AS relationship
    JOIN oltp.occurrence AS occurrence
        ON occurrence.occurrence_id = relationship.occurrence_id
    JOIN oltp.plant AS plant
        ON relationship.asset_type = 'plant'
       AND plant.plant_id = relationship.asset_id
), plant_load AS (
    INSERT INTO data_vault.link_occurrence_power_plant (
        hash_key_link_occ_plant, hash_key_occurrence, hash_key_power_plant,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(hash_key_occurrence, hash_key_power_plant), 'UTF8')), 'hex'),
        hash_key_occurrence, hash_key_power_plant, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM plant_rows
    ON CONFLICT (hash_key_link_occ_plant) DO NOTHING
    RETURNING 1
), substation_rows AS (
    SELECT
        encode(sha256(convert_to(occurrence.ticket_number, 'UTF8')), 'hex') AS hash_key_occurrence,
        encode(sha256(convert_to(substation.substation_code, 'UTF8')), 'hex') AS hash_key_substation
    FROM oltp.occurrence_asset AS relationship
    JOIN oltp.occurrence AS occurrence
        ON occurrence.occurrence_id = relationship.occurrence_id
    JOIN oltp.substation AS substation
        ON relationship.asset_type = 'substation'
       AND substation.substation_id = relationship.asset_id
), substation_load AS (
    INSERT INTO data_vault.link_occurrence_substation (
        hash_key_link_occ_sub, hash_key_occurrence, hash_key_substation,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(hash_key_occurrence, hash_key_substation), 'UTF8')), 'hex'),
        hash_key_occurrence, hash_key_substation, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM substation_rows
    CROSS JOIN (SELECT count(*) FROM plant_load) AS dependency
    ON CONFLICT (hash_key_link_occ_sub) DO NOTHING
    RETURNING 1
), line_rows AS (
    SELECT
        encode(sha256(convert_to(occurrence.ticket_number, 'UTF8')), 'hex') AS hash_key_occurrence,
        encode(sha256(convert_to(line.line_code, 'UTF8')), 'hex') AS hash_key_transmission_line
    FROM oltp.occurrence_asset AS relationship
    JOIN oltp.occurrence AS occurrence
        ON occurrence.occurrence_id = relationship.occurrence_id
    JOIN oltp.transmission_line AS line
        ON relationship.asset_type = 'transmission_line'
       AND line.line_id = relationship.asset_id
), line_load AS (
    INSERT INTO data_vault.link_occurrence_transmission_line (
        hash_key_link_occ_line, hash_key_occurrence, hash_key_transmission_line,
        load_date, record_source
    )
    SELECT
        encode(sha256(convert_to(concat(hash_key_occurrence, hash_key_transmission_line), 'UTF8')), 'hex'),
        hash_key_occurrence, hash_key_transmission_line, CURRENT_TIMESTAMP, 'ONS_OLTP'
    FROM line_rows
    CROSS JOIN (SELECT count(*) FROM substation_load) AS dependency
    ON CONFLICT (hash_key_link_occ_line) DO NOTHING
    RETURNING 1
)
SELECT
    (SELECT count(*) FROM plant_load)
    + (SELECT count(*) FROM substation_load)
    + (SELECT count(*) FROM line_load) AS rows_processed
