"""
### ONS Enterprise Data Pipeline

Orchestrates the existing project code without copying ETL rules into Airflow:

1. generate the deterministic OLTP fixture;
2. load the Raw Vault and Business Vault;
3. publish the Galaxy dimensional model.

Each successful task emits an Airflow Asset event, so the UI also shows the
lineage between the three PostgreSQL layers.
"""

from datetime import timedelta

import pendulum
from airflow.sdk import Asset, dag, task

OLTP_ASSET = Asset("ons://postgres/oltp")
DATA_VAULT_ASSET = Asset("ons://postgres/data-vault")
GALAXY_ASSET = Asset("ons://postgres/galaxy")

STAGE_RUNNER = "bash /opt/airflow/scripts/run_pipeline_stage.sh"


@dag(
    dag_id="ons_enterprise_data_pipeline",
    description="OLTP to Data Vault to Galaxy orchestration for the ONS platform",
    schedule="0 6 * * *",
    start_date=pendulum.datetime(2026, 1, 1, tz="America/Sao_Paulo"),
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=2),
    fail_fast=True,
    default_args={
        "owner": "guilherme-roriz",
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
    },
    tags=["ons", "postgresql", "data-vault", "galaxy"],
)
def ons_enterprise_data_pipeline():
    """Build the daily, idempotent ONS data pipeline."""

    @task.bash(
        task_id="seed_oltp",
        outlets=[OLTP_ASSET],
        execution_timeout=timedelta(minutes=20),
        do_xcom_push=False,
    )
    def seed_oltp() -> str:
        """Create the deterministic operational dataset."""
        return f"{STAGE_RUNNER} seed-oltp"

    @task.bash(
        task_id="load_data_vault",
        inlets=[OLTP_ASSET],
        outlets=[DATA_VAULT_ASSET],
        execution_timeout=timedelta(minutes=40),
        do_xcom_push=False,
    )
    def load_data_vault() -> str:
        """Load OLTP data into the Data Vault model."""
        return f"{STAGE_RUNNER} load-data-vault"

    @task.bash(
        task_id="publish_galaxy",
        inlets=[DATA_VAULT_ASSET],
        outlets=[GALAXY_ASSET],
        execution_timeout=timedelta(minutes=40),
        do_xcom_push=False,
    )
    def publish_galaxy() -> str:
        """Publish the dimensional Galaxy model for analytics."""
        return f"{STAGE_RUNNER} publish-galaxy"

    seed_oltp() >> load_data_vault() >> publish_galaxy()


ons_enterprise_data_pipeline()
