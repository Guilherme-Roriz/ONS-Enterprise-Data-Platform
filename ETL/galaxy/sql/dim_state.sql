INSERT INTO galaxy.dim_state (
    hash_key_state, state_code, state_name, ons_control_area
)
SELECT
    hub.hash_key_state,
    hub.state_code,
    sat.state_name,
    sat.ons_control_area
FROM data_vault.hub_state AS hub
JOIN data_vault.sat_state_attributes AS sat USING (hash_key_state)
ON CONFLICT (hash_key_state) DO UPDATE SET
    state_code = EXCLUDED.state_code,
    state_name = EXCLUDED.state_name,
    ons_control_area = EXCLUDED.ons_control_area
