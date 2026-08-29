from __future__ import annotations

import ast
import json
import re
import unittest
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DAG_PATH = PROJECT_ROOT / "airflow" / "dags" / "ons_enterprise_pipeline.py"
COMPOSE_PATH = PROJECT_ROOT / "compose.yaml"
AIRFLOW_DOCKERFILE_PATH = PROJECT_ROOT / "Dockerfile.airflow"
AIRFLOW_REQUIREMENTS_PATH = PROJECT_ROOT / "airflow" / "requirements.txt"
ENV_EXAMPLE_PATH = PROJECT_ROOT / ".env.example"
STAGE_RUNNER_PATH = PROJECT_ROOT / "airflow" / "scripts" / "run_pipeline_stage.sh"


def assignment_value(tree: ast.AST, name: str) -> ast.AST:
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign):
            continue
        if any(
            isinstance(target, ast.Name) and target.id == name
            for target in node.targets
        ):
            return node.value
    raise AssertionError(f"Assignment {name!r} was not found")


def call_keywords(call: ast.Call) -> dict[str, ast.AST]:
    return {keyword.arg: keyword.value for keyword in call.keywords if keyword.arg}


class AirflowDagTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = DAG_PATH.read_text(encoding="utf-8")
        cls.tree = ast.parse(cls.source, filename=str(DAG_PATH))
        cls.operators: dict[str, dict[str, ast.AST]] = {}

        for task_name in ("seed_oltp", "load_data_vault", "publish_galaxy"):
            value = assignment_value(cls.tree, task_name)
            if not isinstance(value, ast.Call):
                raise AssertionError(f"{task_name} is not created by a call")
            if not isinstance(value.func, ast.Name) or value.func.id != "DockerOperator":
                raise AssertionError(f"{task_name} does not use DockerOperator")
            cls.operators[task_name] = call_keywords(value)

    def test_dag_uses_public_sdk_and_docker_provider(self) -> None:
        imports = {
            node.module: {alias.name for alias in node.names}
            for node in self.tree.body
            if isinstance(node, ast.ImportFrom)
        }

        self.assertEqual({"Asset", "dag"}, imports["airflow.sdk"])
        self.assertEqual(
            {"DockerOperator"},
            imports["airflow.providers.docker.operators.docker"],
        )
        self.assertNotIn("task.bash", self.source)
        self.assertNotIn("run_pipeline_stage", self.source)

    def test_each_task_runs_the_expected_command_in_ons_etl(self) -> None:
        expected_commands = {
            "seed_oltp": ["python", "DDL/populate.py"],
            "load_data_vault": ["python", "-m", "ETL.data_vault.main"],
            "publish_galaxy": ["python", "-m", "ETL.galaxy.main"],
        }
        expected_environments = {
            "seed_oltp": "OLTP_ENVIRONMENT",
            "load_data_vault": "DATA_VAULT_ENVIRONMENT",
            "publish_galaxy": "GALAXY_ENVIRONMENT",
        }

        for task_name, command in expected_commands.items():
            keywords = self.operators[task_name]
            self.assertEqual(task_name, ast.literal_eval(keywords["task_id"]))
            self.assertEqual("ons-etl:local", ast.literal_eval(keywords["image"]))
            self.assertEqual(command, ast.literal_eval(keywords["command"]))
            self.assertEqual("/app", ast.literal_eval(keywords["working_dir"]))
            self.assertIsInstance(keywords["environment"], ast.Name)
            self.assertEqual(
                expected_environments[task_name],
                keywords["environment"].id,
            )

    def test_docker_runtime_contract_is_explicit(self) -> None:
        for keywords in self.operators.values():
            self.assertEqual(
                "unix://var/run/docker.sock",
                ast.literal_eval(keywords["docker_url"]),
            )
            self.assertEqual(
                "ons-network",
                ast.literal_eval(keywords["network_mode"]),
            )
            self.assertFalse(ast.literal_eval(keywords["mount_tmp_dir"]))
            self.assertFalse(ast.literal_eval(keywords["force_pull"]))
            self.assertEqual("success", ast.literal_eval(keywords["auto_remove"]))
            self.assertFalse(ast.literal_eval(keywords["do_xcom_push"]))

    def test_tasks_receive_only_their_workload_environment(self) -> None:
        expected_keys = {
            "OLTP_ENVIRONMENT": {
                "DB_HOST",
                "DB_PORT",
                "DB_NAME",
                "DB_USER",
                "DB_PASSWORD",
            },
            "DATA_VAULT_ENVIRONMENT": {
                "DB_HOST",
                "DB_PORT",
                "DB_NAME",
                "DB_USER",
                "DB_PASSWORD",
            },
            "GALAXY_ENVIRONMENT": {
                "DB_HOST",
                "DB_PORT",
                "DB_NAME",
                "DB_USER",
                "DB_PASSWORD",
                "GALAXY_START_DATE",
                "GALAXY_END_DATE",
                "LOG_LEVEL",
            },
        }

        for environment_name, keys in expected_keys.items():
            environment = ast.literal_eval(
                assignment_value(self.tree, environment_name)
            )
            self.assertEqual(keys, set(environment))
            self.assertNotIn("AIRFLOW_DB_PASSWORD", environment)

        oltp_environment = ast.literal_eval(
            assignment_value(self.tree, "OLTP_ENVIRONMENT")
        )
        etl_environment = ast.literal_eval(
            assignment_value(self.tree, "DATA_VAULT_ENVIRONMENT")
        )
        self.assertTrue(
            all("conn.ons_oltp" in value for value in oltp_environment.values())
        )
        self.assertTrue(
            all("conn.ons_etl" in value for value in etl_environment.values())
        )

    def test_dag_keeps_safety_limits_and_lineage(self) -> None:
        for fragment in (
            'schedule="0 6 * * *"',
            "catchup=False",
            "max_active_runs=1",
            '"retries": 2',
            '"retry_delay": timedelta(minutes=2)',
            "dagrun_timeout=timedelta(hours=2)",
            "execution_timeout=timedelta(minutes=20)",
            "execution_timeout=timedelta(minutes=40)",
            'Asset("ons://postgres/oltp")',
            'Asset("ons://postgres/data-vault")',
            'Asset("ons://postgres/galaxy")',
            "seed_oltp >> load_data_vault >> publish_galaxy",
        ):
            self.assertIn(fragment, self.source)


class AirflowImageTests(unittest.TestCase):
    def test_airflow_image_contains_orchestration_only(self) -> None:
        dockerfile = AIRFLOW_DOCKERFILE_PATH.read_text(encoding="utf-8")

        self.assertIn("airflow/requirements.txt", dockerfile)
        self.assertIn("airflow/dags", dockerfile)
        self.assertNotIn("COPY --chown=airflow:0 ETL", dockerfile)
        self.assertNotIn("COPY --chown=airflow:0 DDL", dockerfile)
        self.assertNotIn("requirements.txt /tmp/requirements/project.txt", dockerfile)
        self.assertNotIn("airflow/scripts", dockerfile)

    def test_docker_provider_is_pinned(self) -> None:
        requirements = AIRFLOW_REQUIREMENTS_PATH.read_text(encoding="utf-8")

        self.assertIn("apache-airflow-providers-docker==4.5.9", requirements)
        self.assertNotIn("apache-airflow-providers-standard", requirements)

    def test_legacy_stage_runner_was_removed(self) -> None:
        self.assertFalse(STAGE_RUNNER_PATH.exists())

    def test_example_environment_declares_three_airflow_secrets(self) -> None:
        environment = ENV_EXAMPLE_PATH.read_text(encoding="utf-8")

        self.assertIn("AIRFLOW_FERNET_KEY=", environment)
        self.assertIn("AIRFLOW_API_SECRET_KEY=", environment)
        self.assertIn("AIRFLOW_API_JWT_SECRET=", environment)


class AirflowComposeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compose = yaml.safe_load(COMPOSE_PATH.read_text(encoding="utf-8"))
        cls.services = cls.compose["services"]

    def test_local_airflow_has_only_the_components_it_needs(self) -> None:
        required = {
            "airflow-db",
            "airflow-init",
            "airflow-api-server",
            "airflow-scheduler",
            "airflow-dag-processor",
        }

        self.assertTrue(required.issubset(self.services))
        self.assertNotIn("redis", self.services)
        self.assertNotIn("airflow-worker", self.services)
        self.assertEqual(
            "LocalExecutor",
            self.services["airflow-scheduler"]["environment"][
                "AIRFLOW__CORE__EXECUTOR"
            ],
        )

    def test_airflow_metadata_is_isolated_from_project_data(self) -> None:
        project_db = self.services["postgres"]
        metadata_db = self.services["airflow-db"]

        self.assertEqual("postgres:17-alpine", project_db["image"])
        self.assertEqual("postgres:17-alpine", metadata_db["image"])
        self.assertNotIn("ports", metadata_db)
        self.assertIn("postgres-data:/var/lib/postgresql/data", project_db["volumes"])
        self.assertIn("airflow-db-data:/var/lib/postgresql/data", metadata_db["volumes"])
        self.assertIn("postgres-data", self.compose["volumes"])
        self.assertIn("airflow-db-data", self.compose["volumes"])

    def test_docker_operator_can_reach_the_daemon_and_project_network(self) -> None:
        scheduler = self.services["airflow-scheduler"]

        self.assertEqual(
            "ons-network",
            self.compose["networks"]["ons-network"]["name"],
        )
        self.assertIn(
            "/var/run/docker.sock:/var/run/docker.sock",
            scheduler["volumes"],
        )
        self.assertEqual(["${DOCKER_GID:-0}"], scheduler["group_add"])
        self.assertIn("ons-network", scheduler["networks"])
        self.assertIn("ons-network", self.services["postgres"]["networks"])

    def test_project_connections_are_limited_to_the_scheduler(self) -> None:
        scheduler_environment = self.services["airflow-scheduler"]["environment"]
        oltp_connection = scheduler_environment["AIRFLOW_CONN_ONS_OLTP"]
        etl_connection = scheduler_environment["AIRFLOW_CONN_ONS_ETL"]

        self.assertIn('"host":"${DOCKER_DB_HOST:-postgres}"', oltp_connection)
        self.assertIn('"login":"${OLTP_USER:-oltp_loader}"', oltp_connection)
        self.assertIn('"login":"${DB_USER:-etl_user}"', etl_connection)
        self.assertNotIn("AIRFLOW_DB_PASSWORD", oltp_connection)
        self.assertNotIn("AIRFLOW_DB_PASSWORD", etl_connection)
        for connection in (oltp_connection, etl_connection):
            resolved = re.sub(r"\$\{[^}]+\}", "safe_value", connection)
            self.assertEqual("generic", json.loads(resolved)["conn_type"])

        for service_name in (
            "airflow-api-server",
            "airflow-dag-processor",
            "airflow-init",
        ):
            environment = self.services[service_name]["environment"]
            self.assertNotIn("AIRFLOW_CONN_ONS_OLTP", environment)
            self.assertNotIn("AIRFLOW_CONN_ONS_ETL", environment)

    def test_airflow_secrets_are_explicit_and_scoped(self) -> None:
        api_environment = self.services["airflow-api-server"]["environment"]
        scheduler_environment = self.services["airflow-scheduler"]["environment"]

        self.assertIn("AIRFLOW__CORE__FERNET_KEY", api_environment)
        self.assertIn("AIRFLOW__CORE__FERNET_KEY", scheduler_environment)
        self.assertIn("AIRFLOW__API__SECRET_KEY", api_environment)
        self.assertIn("AIRFLOW__API__SECRET_KEY", scheduler_environment)
        self.assertIn("AIRFLOW__API_AUTH__JWT_SECRET", api_environment)
        self.assertIn("AIRFLOW__API_AUTH__JWT_SECRET", scheduler_environment)

    def test_new_dag_starts_paused(self) -> None:
        for service_name in (
            "airflow-api-server",
            "airflow-scheduler",
            "airflow-dag-processor",
        ):
            self.assertEqual(
                "true",
                self.services[service_name]["environment"][
                    "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION"
                ],
            )

    def test_long_running_components_wait_for_initialization(self) -> None:
        for service_name in (
            "airflow-api-server",
            "airflow-scheduler",
            "airflow-dag-processor",
        ):
            dependency = self.services[service_name]["depends_on"]["airflow-init"]
            self.assertEqual("service_completed_successfully", dependency["condition"])

    def test_scheduler_waits_for_project_database_and_execution_api(self) -> None:
        dependencies = self.services["airflow-scheduler"]["depends_on"]

        self.assertEqual("service_healthy", dependencies["postgres"]["condition"])
        self.assertEqual(
            "service_healthy",
            dependencies["airflow-api-server"]["condition"],
        )

    def test_original_container_pipeline_is_manual_only(self) -> None:
        for service_name in ("seed-oltp", "oltp-to-vault", "vault-to-galaxy"):
            self.assertEqual(["manual"], self.services[service_name]["profiles"])

    def test_manual_workloads_also_receive_only_needed_environment(self) -> None:
        seed_environment = self.services["seed-oltp"]["environment"]
        vault_environment = self.services["oltp-to-vault"]["environment"]
        galaxy_environment = self.services["vault-to-galaxy"]["environment"]

        database_keys = {
            "DB_HOST",
            "DB_PORT",
            "DB_NAME",
            "DB_USER",
            "DB_PASSWORD",
        }
        self.assertEqual(database_keys, set(seed_environment))
        self.assertEqual(database_keys, set(vault_environment))
        self.assertEqual(
            database_keys
            | {"GALAXY_START_DATE", "GALAXY_END_DATE", "LOG_LEVEL"},
            set(galaxy_environment),
        )


if __name__ == "__main__":
    unittest.main()
