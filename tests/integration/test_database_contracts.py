from __future__ import annotations

from datetime import datetime

import psycopg2
import pytest

from conftest import TEST_ETL_PASSWORD, TEST_ETL_USER, TEST_OLTP_PASSWORD, TEST_OLTP_USER


pytestmark = pytest.mark.integration


def test_roles_are_least_privilege_and_schemas_are_separated(
    test_database, reset_database
):
    reset_database()

    for user, password, forbidden_statement in (
        (
            TEST_ETL_USER,
            TEST_ETL_PASSWORD,
            "INSERT INTO oltp.state (state_code, state_name) VALUES ('ZZ', 'Denied')",
        ),
        (
            TEST_OLTP_USER,
            TEST_OLTP_PASSWORD,
            "INSERT INTO data_vault.hub_state "
            "(hash_key_state, state_code) VALUES (repeat('a', 64), 'ZZ')",
        ),
    ):
        connection = psycopg2.connect(test_database.dsn(user, password))
        try:
            with pytest.raises(psycopg2.errors.InsufficientPrivilege):
                with connection.cursor() as cursor:
                    cursor.execute(forbidden_statement)
            connection.rollback()
        finally:
            connection.close()


def test_oltp_constraints_foreign_keys_and_capacity_trigger(
    admin_connection, reset_database
):
    reset_database()
    with admin_connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO oltp.state (state_code, state_name) "
            "VALUES ('ZZ', 'Test State') RETURNING state_id"
        )
        state_id = cursor.fetchone()[0]
        cursor.execute(
            """
            INSERT INTO oltp.plant (
                plant_code, plant_name, plant_type, installed_capacity,
                state_id, status
            ) VALUES ('PLT-TEST', 'Contract Plant', 'Hydro', 100, %s, 'Active')
            RETURNING plant_id
            """,
            (state_id,),
        )
        plant_id = cursor.fetchone()[0]
    admin_connection.commit()

    with pytest.raises(psycopg2.errors.CheckViolation):
        with admin_connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO oltp.plant (
                    plant_code, plant_name, plant_type, installed_capacity,
                    state_id, status
                ) VALUES ('PLT-BAD-CAP', 'Bad', 'Hydro', 0, %s, 'Active')
                """,
                (state_id,),
            )
    admin_connection.rollback()

    with pytest.raises(psycopg2.errors.ForeignKeyViolation):
        with admin_connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO oltp.plant (
                    plant_code, plant_name, plant_type, installed_capacity,
                    state_id, status
                ) VALUES ('PLT-BAD-FK', 'Bad', 'Hydro', 10, -1, 'Active')
                """
            )
    admin_connection.rollback()

    with pytest.raises(psycopg2.errors.RaiseException):
        with admin_connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO oltp.generation_reading (
                    plant_id, reading_timestamp, generation_output_mw,
                    available_capacity_mw
                ) VALUES (%s, %s, 50, 101)
                """,
                (plant_id, datetime(2026, 7, 1)),
            )
    admin_connection.rollback()


def test_transaction_rolls_back_all_prior_writes_and_can_be_retried(
    admin_connection, reset_database
):
    reset_database()

    with pytest.raises(psycopg2.errors.CheckViolation):
        with admin_connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO oltp.state (state_code, state_name) "
                "VALUES ('RB', 'Must Roll Back')"
            )
            cursor.execute(
                """
                INSERT INTO oltp.occurrence_type (
                    type_code, category, subtype, severity_level
                ) VALUES ('BAD', 'Invalid Category', 'Bad', 'Low')
                """
            )
        admin_connection.commit()
    admin_connection.rollback()

    with admin_connection.cursor() as cursor:
        cursor.execute("SELECT count(*) FROM oltp.state WHERE state_code = 'RB'")
        assert cursor.fetchone()[0] == 0
        cursor.execute(
            "INSERT INTO oltp.state (state_code, state_name) "
            "VALUES ('RB', 'Successful Retry')"
        )
    admin_connection.commit()

    with admin_connection.cursor() as cursor:
        cursor.execute("SELECT state_name FROM oltp.state WHERE state_code = 'RB'")
        assert cursor.fetchone()[0] == "Successful Retry"
