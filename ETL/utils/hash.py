"""
Utility to compute SHA-256 hashes for Data Vault business keys.
"""
import hashlib

def generate_hash(value: str) -> str:
    """
    Return SHA-256 hex digest of the input string.
    Used for hub hash keys, link hash keys, and satellite hashdiffs.
    """
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
