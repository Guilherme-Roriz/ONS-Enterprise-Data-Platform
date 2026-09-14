"""Deterministic SHA-256 helpers used by Data Vault contracts."""
import hashlib


NULL_SENTINEL = "∅"


def generate_hash(value: str) -> str:
    """
    Return SHA-256 hex digest of the input string.
    Used for hub hash keys, link hash keys, and satellite hashdiffs.
    """
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def generate_hashdiff(*values: object) -> str:
    """Hash an ordered record using the SQL pipeline's delimiter and null token."""
    canonical = "|".join(
        NULL_SENTINEL if value is None else str(value) for value in values
    )
    return generate_hash(canonical)
