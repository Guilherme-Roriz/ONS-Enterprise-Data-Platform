"""
Load data into Data Vault Hub tables.
"""
import logging
import pandas as pd
from sqlalchemy import text, Connection
from ETL.utils.hash import generate_hash

logger = logging.getLogger(__name__)

class HubLoader:
    """Insert new business keys into a Hub table."""

    @staticmethod
    def load(conn: Connection, mapping: dict, df: pd.DataFrame) -> None:
        """
        Load distinct business keys from the source DataFrame into the Hub.

        Expects mapping keys:
            hub_table, business_key, hub_hash_key_column, hub_business_key_column
        """
        hub_table = mapping["hub_table"]
        business_key_col = mapping["business_key"]
        hub_hash_col = mapping["hub_hash_key_column"]
        hub_bk_col = mapping["hub_business_key_column"]
        load_date_col = mapping.get("load_date_column", "load_datetime")

        # Extract distinct business keys with their load dates (take first occurrence)
        distinct_keys = (
            df[[business_key_col, load_date_col]]
            .drop_duplicates(subset=[business_key_col])
            .copy()
        )
        if distinct_keys.empty:
            logger.info("No business keys to load for Hub %s", hub_table)
            return

        # Compute hub hash key
        distinct_keys[hub_hash_col] = distinct_keys[business_key_col].astype(str).apply(generate_hash)

        rows_inserted = 0
        for _, row in distinct_keys.iterrows():
            insert_sql = text(f"""
                INSERT INTO {hub_table} ({hub_hash_col}, {hub_bk_col}, {load_date_col})
                VALUES (:hash_key, :bk, :load_date)
                ON CONFLICT ({hub_hash_col}) DO NOTHING
            """)
            result = conn.execute(
                insert_sql,
                {
                    "hash_key": row[hub_hash_col],
                    "bk": row[business_key_col],
                    "load_date": row[load_date_col],
                },
            )
            if result.rowcount:
                rows_inserted += 1

        logger.info(
            "Hub %s: %d distinct keys found, %d new keys inserted",
            hub_table, len(distinct_keys), rows_inserted,
        )
