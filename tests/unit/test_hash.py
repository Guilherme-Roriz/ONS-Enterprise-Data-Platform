from __future__ import annotations

import hashlib

import pytest

from ETL.utils.hash import generate_hash, generate_hashdiff


pytestmark = pytest.mark.unit


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("PLT-001", hashlib.sha256(b"PLT-001").hexdigest()),
        ("São Paulo", hashlib.sha256("São Paulo".encode("utf-8")).hexdigest()),
        ("", hashlib.sha256(b"").hexdigest()),
    ],
)
def test_generate_hash_matches_sha256_utf8(value: str, expected: str) -> None:
    assert generate_hash(value) == expected
    assert len(generate_hash(value)) == 64


def test_generate_hash_is_deterministic_and_case_sensitive() -> None:
    assert generate_hash("PLT-001") == generate_hash("PLT-001")
    assert generate_hash("PLT-001") != generate_hash("plt-001")


def test_generate_hashdiff_preserves_order_and_nulls() -> None:
    expected = hashlib.sha256("Hydro|∅|100.00".encode("utf-8")).hexdigest()
    assert generate_hashdiff("Hydro", None, "100.00") == expected
    assert generate_hashdiff("Hydro", None, "100.00") != generate_hashdiff(
        None, "Hydro", "100.00"
    )


def test_generate_hash_rejects_non_text_business_key() -> None:
    with pytest.raises(AttributeError):
        generate_hash(123)  # type: ignore[arg-type]

