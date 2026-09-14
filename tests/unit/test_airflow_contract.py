from __future__ import annotations

import ast
import json
import re
from pathlib import Path

import pytest
import yaml


pytestmark = pytest.mark.unit
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DAG_PATH = PROJECT_ROOT / "airflow" / "dags" / "ons_enterprise_pipeline.py"


def assignment_value(tree: ast.AST, name: str) -> ast.AST:
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == name
            for target in node.targets
        ):
            return node.value
    raise AssertionError(f"assignment {name!r} was not found")


@pytest.fixture(scope="module")
def dag_contract() -> tuple[str, ast.Module, dict[str, dict[str, ast.AST]]]:
    source = DAG_PATH.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(DAG_PATH))
    operators: dict[str, dict[str, ast.AST]] = {}
    for task_name in ("seed_oltp", "load_data_vault", "publish_galaxy"):
        value = assignment_value(tree, task_name)
        assert isinstance(value, ast.Call)
        assert isinstance(value.func, ast.Name) and value.func.id == "DockerOperator"
        operators[task_name] = {
            keyword.arg: keyword.value for keyword in value.keywords if keyword.arg
        }
    return source, tree, operators


def test_dag_runs_three_expected_commands(dag_contract) -> None:
    _, _, operators = dag_contract
    expected = {
        "seed_oltp": ["python", "DDL/populate.py"],
        "load_data_vault": ["python", "-m", "ETL.data_vault.main"],
        "publish_galaxy": ["python", "-m", "ETL.galaxy.main"],
    }
    for task, command in expected.items():
        assert ast.literal_eval(operators[task]["task_id"]) == task
        assert ast.literal_eval(operators[task]["image"]) == "ons-etl:local"
        assert ast.literal_eval(operators[task]["command"]) == command
        assert ast.literal_eval(operators[task]["network_mode"]) == "ons-network"
        assert ast.literal_eval(operators[task]["auto_remove"]) == "success"


def test_dag_preserves_failure_and_lineage_contract(dag_contract) -> None:
    source, _, _ = dag_contract
    for fragment in (
        'schedule="0 6 * * *"',
        "catchup=False",
        "max_active_runs=1",
        "fail_fast=True",
        '"retries": 2',
        "dagrun_timeout=timedelta(hours=2)",
        'Asset("ons://postgres/oltp")',
        'Asset("ons://postgres/data-vault")',
        'Asset("ons://postgres/galaxy")',
        "seed_oltp >> load_data_vault >> publish_galaxy",
    ):
        assert fragment in source


def test_workload_secrets_are_scoped(dag_contract) -> None:
    _, tree, _ = dag_contract
    expected = {
        "OLTP_ENVIRONMENT": {"DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"},
        "DATA_VAULT_ENVIRONMENT": {"DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"},
        "GALAXY_ENVIRONMENT": {
            "DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD",
            "GALAXY_START_DATE", "GALAXY_END_DATE", "LOG_LEVEL",
        },
    }
    for name, keys in expected.items():
        environment = ast.literal_eval(assignment_value(tree, name))
        assert set(environment) == keys
        assert "AIRFLOW_DB_PASSWORD" not in environment


def test_compose_keeps_test_and_production_runtime_boundaries() -> None:
    compose = yaml.safe_load((PROJECT_ROOT / "compose.yaml").read_text(encoding="utf-8"))
    services = compose["services"]
    assert {"postgres", "airflow-db", "airflow-api-server", "airflow-scheduler"} <= set(services)
    assert "redis" not in services
    assert "airflow-worker" not in services
    assert services["airflow-scheduler"]["environment"]["AIRFLOW__CORE__EXECUTOR"] == "LocalExecutor"
    assert "/var/run/docker.sock:/var/run/docker.sock" in services["airflow-scheduler"]["volumes"]
    for name in ("seed-oltp", "oltp-to-vault", "vault-to-galaxy"):
        assert services[name]["profiles"] == ["manual"]


def test_airflow_connections_are_valid_and_separate() -> None:
    compose = yaml.safe_load((PROJECT_ROOT / "compose.yaml").read_text(encoding="utf-8"))
    environment = compose["services"]["airflow-scheduler"]["environment"]
    oltp = environment["AIRFLOW_CONN_ONS_OLTP"]
    etl = environment["AIRFLOW_CONN_ONS_ETL"]
    assert '"login":"${OLTP_USER:-oltp_loader}"' in oltp
    assert '"login":"${DB_USER:-etl_user}"' in etl
    for connection in (oltp, etl):
        resolved = re.sub(r"\$\{[^}]+\}", "safe_value", connection)
        assert json.loads(resolved)["conn_type"] == "generic"


def test_airflow_image_contains_orchestration_only() -> None:
    dockerfile = (PROJECT_ROOT / "Dockerfile.airflow").read_text(encoding="utf-8")
    requirements = (PROJECT_ROOT / "airflow" / "requirements.txt").read_text(encoding="utf-8")
    assert "airflow/dags" in dockerfile
    assert "COPY --chown=airflow:0 ETL" not in dockerfile
    assert "COPY --chown=airflow:0 DDL" not in dockerfile
    assert "apache-airflow-providers-docker==4.5.9" in requirements

