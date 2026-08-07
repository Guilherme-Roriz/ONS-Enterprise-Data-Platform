"""
Load data into Data Vault Satellite tables.
Uses SHA-256 hashdiff to detect changes.
"""
import logging
import pandas as pd
from sqlalchemy import text, Connection
from ETL.utils.hash import generate_hash

logger = logging.getLogger(__name__)

class SatelliteLoader:
    """Insert satellite rows only when the hashdiff differs from the latest version."""

    @staticmethod
    def load(conn: Connection, mapping: dict, df: pd.DataFrame) -> None:
        """
        Compare source rows with the current latest satellite row and insert changed records.

        Expected mapping keys:
            satellite_table, business_key, hub_hash_key_column, satellite_hub_key_column,
            satellite_hashdiff_column, load_date_column, hash_columns
        """
        sat_table = mapping["satellite_table"]
        business_key_col = mapping["business_key"]
        hub_hash_col = mapping["hub_hash_key_column"]
        sat_hub_col = mapping["satellite_hub_key_column"]
        sat_hash_col = mapping["satellite_hashdiff_column"]
        load_date_col = mapping["load_date_column"]
        hash_cols = mapping["hash_columns"]

        if df.empty:
            logger.info("No rows for satellite %s", sat_table)
            return

        # Compute hub hash key for every row
        df[hub_hash_col] = df[business_key_col].astype(str).apply(generate_hash)

        # Compute row hashdiff: SHA-256 of concatenated descriptive columns
        def compute_row_hash(row: pd.Series) -> str:
            values = [str(row[col]) for col in hash_cols]
            return generate_hash("|".join(values))

        df["_hash_diff"] = df.apply(compute_row_hash, axis=1)

        # We need to check the latest hash for each hub key in the satellite.
        # To minimise per-row lookups, we fetch the latest row per hub key from the satellite table.
        latest_query = text(f"""
            SELECT DISTINCT ON ({sat_hub_col})
                {sat_hub_col}, {sat_hash_col}
            FROM {sat_table}
            ORDER BY {sat_hub_col}, {load_date_col} DESC
        """)
        latest_df = pd.read_sql(latest_query, conn)
        latest_map = (
            latest_df.set_index(sat_hub_col)[sat_hash_col].to_dict()
            if not latest_df.empty
            else {}
        )

        inserts = 0
        skips = 0
        for _, row in df.iterrows():
            hub_key = row[hub_hash_col]
            new_hash = row["_hash_diff"]
            old_hash = latest_map.get(hub_key)

            if old_hash is None or old_hash != new_hash:
                # Build dynamic column list from the row's values.
                # We insert all descriptive columns + system columns.
                # The satellite table is assumed to have columns matching:
                # {sat_hub_col}, {load_date_col}, {sat_hash_col}, and all hash_columns.
                columns = [sat_hub_col, load_date_col, sat_hash_col] + hash_cols
                placeholders = ", ".join([f":{col}" for col in columns])
                col_list = ", ".join(columns)
                insert_sql = text(f"""
                    INSERT INTO {sat_table} ({col_list})
                    VALUES ({placeholders})
                """)
                params = {col: row[col] for col in columns}
                params[sat_hash_col] = new_hash
                conn.execute(insert_sql, params)
                inserts += 1
            else:
                skips += 1

        logger.info(
            "Satellite %s: %d rows processed, %d inserted, %d skipped (no change)",
            sat_table, len(df), inserts, skips,
        )
