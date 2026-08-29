"""
### ONS Enterprise Data Pipeline

Airflow orchestrates three isolated containers from the existing
`ons-etl:local` image:

1. generate the deterministic OLTP fixture;
2. load the Raw Vault and Business Vault;
3. publish the Galaxy dimensional model.

The DockerOperator sends each container only the environment needed for its
workload. Each successful task emits an Airflow Asset event, so the UI also
shows the lineage between the three PostgreSQL layers.
"""

from datetime import timedelta

import pendulum
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import Asset, dag

OLTP_ASSET = Asset("ons://postgres/oltp")
DATA_VAULT_ASSET = Asset("ons://postgres/data-vault")
GALAXY_ASSET = Asset("ons://postgres/galaxy")

OLTP_ENVIRONMENT = {
    "DB_HOST": "{{ conn.ons_oltp.host }}",
    "DB_PORT": "{{ conn.ons_oltp.port }}",
    "DB_NAME": "{{ conn.ons_oltp.schema }}",
    "DB_USER": "{{ conn.ons_oltp.login }}",
    "DB_PASSWORD": "{{ conn.ons_oltp.password }}",
}

DATA_VAULT_ENVIRONMENT = {
    "DB_HOST": "{{ conn.ons_etl.host }}",
    "DB_PORT": "{{ conn.ons_etl.port }}",
    "DB_NAME": "{{ conn.ons_etl.schema }}",
    "DB_USER": "{{ conn.ons_etl.login }}",
    "DB_PASSWORD": "{{ conn.ons_etl.password }}",
}

GALAXY_ENVIRONMENT = {
    "DB_HOST": "{{ conn.ons_etl.host }}",
    "DB_PORT": "{{ conn.ons_etl.port }}",
    "DB_NAME": "{{ conn.ons_etl.schema }}",
    "DB_USER": "{{ conn.ons_etl.login }}",
    "DB_PASSWORD": "{{ conn.ons_etl.password }}",
    "GALAXY_START_DATE": "{{ var.value.galaxy_start_date }}",
    "GALAXY_END_DATE": "{{ var.value.galaxy_end_date }}",
    "LOG_LEVEL": "{{ var.value.pipeline_log_level }}",
}


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

    seed_oltp = DockerOperator(
        task_id="seed_oltp",
        image="ons-etl:local",
        command=["python", "DDL/populate.py"],
        docker_url="unix://var/run/docker.sock",
        api_version="auto",
        network_mode="ons-network",
        environment=OLTP_ENVIRONMENT,
        working_dir="/app",
        mount_tmp_dir=False,
        force_pull=False,
        auto_remove="success",
        outlets=[OLTP_ASSET],
        execution_timeout=timedelta(minutes=20),
        do_xcom_push=False,
        labels={
            "ons.pipeline": "ons_enterprise_data_pipeline",
            "ons.task": "seed_oltp",
        },
    )

    load_data_vault = DockerOperator(
        task_id="load_data_vault",
        image="ons-etl:local",
        command=["python", "-m", "ETL.data_vault.main"],
        docker_url="unix://var/run/docker.sock",
        api_version="auto",
        network_mode="ons-network",
        environment=DATA_VAULT_ENVIRONMENT,
        working_dir="/app",
        mount_tmp_dir=False,
        force_pull=False,
        auto_remove="success",
        inlets=[OLTP_ASSET],
        outlets=[DATA_VAULT_ASSET],
        execution_timeout=timedelta(minutes=40),
        do_xcom_push=False,
        labels={
            "ons.pipeline": "ons_enterprise_data_pipeline",
            "ons.task": "load_data_vault",
        },
    )

    publish_galaxy = DockerOperator(
        task_id="publish_galaxy",
        image="ons-etl:local",
        command=["python", "-m", "ETL.galaxy.main"],
        docker_url="unix://var/run/docker.sock",
        api_version="auto",
        network_mode="ons-network",
        environment=GALAXY_ENVIRONMENT,
        working_dir="/app",
        mount_tmp_dir=False,
        force_pull=False,
        auto_remove="success",
        inlets=[DATA_VAULT_ASSET],
        outlets=[GALAXY_ASSET],
        execution_timeout=timedelta(minutes=40),
        do_xcom_push=False,
        labels={
            "ons.pipeline": "ons_enterprise_data_pipeline",
            "ons.task": "publish_galaxy",
        },
    )

    seed_oltp >> load_data_vault >> publish_galaxy


ons_enterprise_data_pipeline()
