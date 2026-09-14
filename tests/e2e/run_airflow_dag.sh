#!/usr/bin/env bash
set -euo pipefail

dag_id="ons_enterprise_data_pipeline"
run_id="${1:?usage: run_airflow_dag.sh RUN_ID}"
timeout_seconds="${AIRFLOW_E2E_TIMEOUT_SECONDS:-900}"
project_name="${COMPOSE_PROJECT_NAME:-ons-airflow-e2e}"
airflow_db_user="${AIRFLOW_DB_USER:-airflow}"
airflow_db_name="${AIRFLOW_DB_NAME:-airflow}"
compose=(docker compose -p "$project_name" -f compose.yaml)

deadline=$((SECONDS + timeout_seconds))
until "${compose[@]}" exec -T airflow-scheduler airflow dags list 2>/dev/null \
    | grep -Fq "$dag_id"; do
    if (( SECONDS >= deadline )); then
        echo "DAG $dag_id was not discovered within ${timeout_seconds}s" >&2
        exit 1
    fi
    sleep 5
done

"${compose[@]}" exec -T airflow-scheduler \
    airflow dags list-import-errors --output table
import_error_count="$(
    "${compose[@]}" exec -T airflow-db \
        psql -U "$airflow_db_user" -d "$airflow_db_name" -Atqc \
        "SELECT count(*) FROM import_error"
)"
if [[ "$import_error_count" != "0" ]]; then
    echo "Airflow reported $import_error_count DAG import error(s)" >&2
    exit 1
fi

"${compose[@]}" exec -T airflow-scheduler airflow dags unpause "$dag_id"
"${compose[@]}" exec -T airflow-scheduler \
    airflow dags trigger --run-id "$run_id" "$dag_id"

deadline=$((SECONDS + timeout_seconds))
while true; do
    state="$(
        "${compose[@]}" exec -T airflow-db \
            psql -U "$airflow_db_user" -d "$airflow_db_name" -Atqc \
            "SELECT state FROM dag_run WHERE dag_id = '$dag_id' AND run_id = '$run_id'"
    )"
    case "$state" in
        success)
            break
            ;;
        failed)
            echo "DAG run $run_id failed" >&2
            "${compose[@]}" exec -T airflow-db \
                psql -U "$airflow_db_user" -d "$airflow_db_name" -P pager=off -c \
                "SELECT task_id, state, try_number FROM task_instance WHERE dag_id = '$dag_id' AND run_id = '$run_id' ORDER BY task_id"
            exit 1
            ;;
    esac
    if (( SECONDS >= deadline )); then
        echo "DAG run $run_id did not finish within ${timeout_seconds}s; state=${state:-missing}" >&2
        exit 1
    fi
    sleep 5
done

actual_tasks="$(
    "${compose[@]}" exec -T airflow-db \
        psql -U "$airflow_db_user" -d "$airflow_db_name" -Atqc \
        "SELECT task_id || '=' || COALESCE(state, 'NULL') FROM task_instance WHERE dag_id = '$dag_id' AND run_id = '$run_id' ORDER BY task_id"
)"
expected_tasks=$'load_data_vault=success\npublish_galaxy=success\nseed_oltp=success'
if [[ "$actual_tasks" != "$expected_tasks" ]]; then
    echo "Unexpected task states for $run_id:" >&2
    echo "$actual_tasks" >&2
    exit 1
fi

echo "DAG run $run_id completed with all DockerOperator tasks successful"
