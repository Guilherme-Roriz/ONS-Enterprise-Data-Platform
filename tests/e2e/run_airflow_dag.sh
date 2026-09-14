#!/usr/bin/env bash
set -euo pipefail

dag_id="ons_enterprise_data_pipeline"
run_id="${1:?usage: run_airflow_dag.sh scheduled|RUN_ID}"
# IDs are interpolated into read-only metadata queries below.
[[ "$run_id" =~ ^[a-zA-Z0-9_.:+-]+$ ]] || exit 2
timeout_seconds="${AIRFLOW_E2E_TIMEOUT_SECONDS:-900}"
project_name="${COMPOSE_PROJECT_NAME:-ons-airflow-e2e}"
airflow_db_user="${AIRFLOW_DB_USER:-airflow}"
airflow_db_name="${AIRFLOW_DB_NAME:-airflow}"
compose=(docker compose -p "$project_name" -f compose.yaml)

deadline=$((SECONDS + timeout_seconds))
until "${compose[@]}" exec -T airflow-scheduler airflow dags list 2>/dev/null \
    | grep -F "$dag_id" >/dev/null; do
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
if [[ "$run_id" == "scheduled" ]]; then
    # A fresh, unpaused DAG creates its latest due daily run. Prove this
    # scheduler behavior before submitting a manual idempotency rerun.
    deadline=$((SECONDS + timeout_seconds))
    while true; do
        run_id="$(
            "${compose[@]}" exec -T airflow-db \
                psql -U "$airflow_db_user" -d "$airflow_db_name" -Atqc \
                "SELECT run_id FROM dag_run WHERE dag_id = '$dag_id' AND run_type = 'scheduled' ORDER BY id LIMIT 1"
        )"
        [[ -n "$run_id" ]] && break
        if (( SECONDS >= deadline )); then
            echo "Scheduler did not create a daily DAG run" >&2
            exit 1
        fi
        sleep 5
    done
    [[ "$run_id" =~ ^[a-zA-Z0-9_.:+-]+$ ]] || exit 2
else
    "${compose[@]}" exec -T airflow-scheduler \
        airflow dags trigger --run-id "$run_id" "$dag_id"
fi

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

execution_contract="$(
    "${compose[@]}" exec -T airflow-db \
        psql -U "$airflow_db_user" -d "$airflow_db_name" -Atqc \
        "SELECT count(*) FROM task_instance seed
         JOIN task_instance vault USING (dag_id, run_id)
         JOIN task_instance galaxy USING (dag_id, run_id)
         WHERE seed.dag_id = '$dag_id' AND seed.run_id = '$run_id'
           AND seed.task_id = 'seed_oltp'
           AND vault.task_id = 'load_data_vault'
           AND galaxy.task_id = 'publish_galaxy'
           AND seed.operator = 'DockerOperator'
           AND vault.operator = 'DockerOperator'
           AND galaxy.operator = 'DockerOperator'
           AND seed.end_date <= vault.start_date
           AND vault.end_date <= galaxy.start_date"
)"
[[ "$execution_contract" == "1" ]] || {
    echo "DockerOperator type or dependency execution order is invalid" >&2
    exit 1
}
"${compose[@]}" exec -T airflow-db \
    psql -U "$airflow_db_user" -d "$airflow_db_name" -P pager=off -c \
    "SELECT task_id, operator, state, try_number, start_date, end_date FROM task_instance WHERE dag_id = '$dag_id' AND run_id = '$run_id' ORDER BY start_date"
echo "DAG run $run_id completed with all DockerOperator tasks successful"
