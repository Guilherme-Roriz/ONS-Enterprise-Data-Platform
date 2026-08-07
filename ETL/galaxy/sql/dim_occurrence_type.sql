INSERT INTO galaxy.dim_occurrence_type (
    hash_key_occurrence_type, occurrence_category,
    occurrence_subtype, severity_level
)
SELECT
    hub.hash_key_occurrence_type,
    sat.category,
    sat.subtype,
    sat.severity_level
FROM data_vault.hub_occurrence_type AS hub
JOIN data_vault.sat_occurrence_type_attributes AS sat USING (hash_key_occurrence_type)
ON CONFLICT (hash_key_occurrence_type) DO UPDATE SET
    occurrence_category = EXCLUDED.occurrence_category,
    occurrence_subtype = EXCLUDED.occurrence_subtype,
    severity_level = EXCLUDED.severity_level
