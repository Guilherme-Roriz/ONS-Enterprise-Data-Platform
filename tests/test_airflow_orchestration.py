from __future__ import annotations

import ast
import unittest
from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DAG_PATH = PROJECT_ROOT / "airflow" / "dags" / "ons_enterprise_pipeline.py"
COMPOSE_PATH = PROJECT_ROOT / "compose.yaml"
STAGE_RUNNER_PATH = (
    PROJECT_ROOT / "airflow" / "scripts" / "run_pipeline_stage.sh"
)


class AirflowDagTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = DAG_PATH.read_text(encoding="utf-8")
        cls.tree = ast.parse(cls.source, filename=str(DAG_PATH))

    def test_dag_uses_the_airflow_3_public_sdk(self) -> None:
        sdk_imports = {
            alias.name
            for node in self.tree.body
            if isinstance(node, ast.ImportFrom) and node.module == "airflow.sdk"
            for alias in node.names
        }

        self.assertEqual({"Asset", "dag", "task"}, sdk_imports)
        self.assertNotIn("airflow.models", self.source)
        self.assertNotIn("airflow.decorators", self.source)

    def test_dag_declares_the_three_pipeline_tasks(self) -> None:
        task_ids = set()
        for node in ast.walk(self.tree):
            if not isinstance(node, ast.FunctionDef):
                continue
            for decorator in node.decorator_list:
                if not isinstance(decorator, ast.Call):
                    continue
                for keyword in decorator.keywords:
                    if keyword.arg == "task_id" and isinstance(
                        keyword.value, ast.Constant
                    ):
                        task_ids.add(keyword.value.value)

        self.assertEqual(
            {"seed_oltp", "load_data_vault", "publish_galaxy"},
            task_ids,
        )

    def test_dag_is_bounded_and_safe_to_rerun(self) -> None:
        self.assertIn('schedule="0 6 * * *"', self.source)
        self.assertIn("catchup=False", self.source)
        self.assertIn("max_active_runs=1", self.source)
        self.assertIn("fail_fast=True", self.source)
        self.assertIn("do_xcom_push=False", self.source)

    def test_dag_exposes_data_layer_lineage(self) -> None:
        self.assertIn('Asset("ons://postgres/oltp")', self.source)
        self.assertIn('Asset("ons://postgres/data-vault")', self.source)
        self.assertIn('Asset("ons://postgres/galaxy")', self.source)
        self.assertIn(
            "seed_oltp() >> load_data_vault() >> publish_galaxy()",
            self.source,
        )


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
        metadata_db = self.services["airflow-db"]

        self.assertEqual("postgres:17-alpine", metadata_db["image"])
        self.assertNotIn("ports", metadata_db)
        self.assertIn("airflow-db-data:/var/lib/postgresql/data", metadata_db["volumes"])
        self.assertIn("postgres-data", self.compose["volumes"])
        self.assertIn("airflow-db-data", self.compose["volumes"])

    def test_project_credentials_are_limited_to_the_scheduler(self) -> None:
        scheduler_environment = self.services["airflow-scheduler"]["environment"]
        self.assertIn("ETL_DB_PASSWORD", scheduler_environment)
        self.assertIn("OLTP_DB_PASSWORD", scheduler_environment)

        for service_name in ("airflow-api-server", "airflow-dag-processor"):
            environment = self.services[service_name]["environment"]
            self.assertNotIn("ETL_DB_PASSWORD", environment)
            self.assertNotIn("OLTP_DB_PASSWORD", environment)

    def test_long_running_components_wait_for_initialization(self) -> None:
        for service_name in (
            "airflow-api-server",
            "airflow-scheduler",
            "airflow-dag-processor",
        ):
            dependency = self.services[service_name]["depends_on"]["airflow-init"]
            self.assertEqual("service_completed_successfully", dependency["condition"])

    def test_scheduler_waits_for_the_execution_api(self) -> None:
        dependency = self.services["airflow-scheduler"]["depends_on"][
            "airflow-api-server"
        ]

        self.assertEqual("service_healthy", dependency["condition"])

    def test_original_container_pipeline_remains_available_as_a_profile(self) -> None:
        for service_name in ("seed-oltp", "oltp-to-vault", "vault-to-galaxy"):
            self.assertEqual(["manual"], self.services[service_name]["profiles"])


class PipelineStageRunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = STAGE_RUNNER_PATH.read_text(encoding="utf-8")

    def test_shell_runner_fails_fast(self) -> None:
        self.assertIn("set -Eeuo pipefail", self.source)
        self.assertIn("Unknown pipeline stage", self.source)

    def test_each_stage_calls_the_existing_project_entrypoint(self) -> None:
        self.assertIn("python DDL/populate.py", self.source)
        self.assertIn("python -m ETL.data_vault.main", self.source)
        self.assertIn("python -m ETL.galaxy.main", self.source)


if __name__ == "__main__":
    unittest.main()
