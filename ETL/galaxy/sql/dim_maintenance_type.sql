INSERT INTO galaxy.dim_maintenance_type (
    hash_key_maintenance_type, maintenance_category,
    maintenance_subtype, priority_level
)
SELECT
    hub.hash_key_maintenance_type,
    sat.category,
    sat.subtype,
    sat.priority_level
FROM data_vault.hub_maintenance_type AS hub
JOIN data_vault.sat_maintenance_type_attributes AS sat USING (hash_key_maintenance_type)
ON CONFLICT (hash_key_maintenance_type) DO UPDATE SET
    maintenance_category = EXCLUDED.maintenance_category,
    maintenance_subtype = EXCLUDED.maintenance_subtype,
    priority_level = EXCLUDED.priority_level
