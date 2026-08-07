"""
Load data into Data Vault Link tables.
"""
import logging
import pandas as pd
from sqlalchemy import text, Connection
from ETL.utils.hash import generate_hash

logger = logging.getLogger(__name__)

class LinkLoader:
    """Insert rows into Link tables based on mapping definitions."""

    @staticmethod
    def load(conn: Connection, mapping: dict, df: pd.DataFrame) -> None:
        """
        For each link definition in the mapping, compute left and right hub hash keys
        and insert into the link table.

        Link definition keys:
            link_table, left_source_column, right_source_column,
            left_hub_hash_key_column, right_hub_hash_key_column,
            left_link_key_column, right_link_key_column
        """
        links = mapping.get("links", [])
        if not links:
            return

        for link_def in links:
            link_table = link_def["link_table"]
            left_src_col = link_def["left_source_column"]
            right_src_col = link_def["right_source_column"]
            left_hash_col = link_def["left_hub_hash_key_column"]
            right_hash_col = link_def["right_hub_hash_key_column"]
            left_link_col = link_def["left_link_key_column"]
            right_link_col = link_def["right_link_key_column"]
            load_date_col = mapping.get("load_date_column", "load_datetime")

            # Compute hub hashes for left and right
            df_copy = df[[left_src_col, right_src_col, load_date_col]].dropna().copy()
            if df_copy.empty:
                logger.info("No valid rows for link %s", link_table)
                continue

            df_copy[left_hash_col] = df_copy[left_src_col].astype(str).apply(generate_hash)
            df_copy[right_hash_col] = df_copy[right_src_col].astype(str).apply(generate_hash)

            # Deduplicate link pairs
            unique_links = df_copy.drop_duplicates(subset=[left_src_col, right_src_col])

            rows_inserted = 0
            for _, row in unique_links.iterrows():
                insert_sql = text(f"""
                    INSERT INTO {link_table} ({left_link_col}, {right_link_col}, {load_date_col})
                    VALUES (:left_hash, :right_hash, :load_date)
                    ON CONFLICT ({left_link_col}, {right_link_col}) DO NOTHING
                """)
                result = conn.execute(
                    insert_sql,
                    {
                        "left_hash": row[left_hash_col],
                        "right_hash": row[right_hash_col],
                        "load_date": row[load_date_col],
                    },
                )
                if result.rowcount:
                    rows_inserted += 1

            logger.info(
                "Link %s: %d unique pairs found, %d inserted",
                link_table, len(unique_links), rows_inserted,
            )
