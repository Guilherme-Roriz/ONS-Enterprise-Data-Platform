#!/usr/bin/env bash
set -Eeuo pipefail

stage="${1:-}"
project_dir="${PIPELINE_PROJECT_DIR:-/opt/airflow/project}"

require_env() {
    local variable_name="$1"

    if [[ -z "${!variable_name:-}" ]]; then
        echo "Required environment variable ${variable_name} is not set." >&2
        exit 1
    fi
}

for variable_name in DB_HOST DB_PORT DB_NAME; do
    require_env "$variable_name"
done

case "$stage" in
    seed-oltp)
        require_env OLTP_DB_USER
        require_env OLTP_DB_PASSWORD
        export DB_USER="$OLTP_DB_USER"
        export DB_PASSWORD="$OLTP_DB_PASSWORD"
        command=(python DDL/populate.py)
        ;;
    load-data-vault)
        require_env ETL_DB_USER
        require_env ETL_DB_PASSWORD
        export DB_USER="$ETL_DB_USER"
        export DB_PASSWORD="$ETL_DB_PASSWORD"
        command=(python -m ETL.data_vault.main)
        ;;
    publish-galaxy)
        require_env ETL_DB_USER
        require_env ETL_DB_PASSWORD
        export DB_USER="$ETL_DB_USER"
        export DB_PASSWORD="$ETL_DB_PASSWORD"
        command=(python -m ETL.galaxy.main)
        ;;
    *)
        echo "Unknown pipeline stage: ${stage:-<empty>}." >&2
        exit 2
        ;;
esac

if [[ ! -d "$project_dir" ]]; then
    echo "Pipeline project directory does not exist: ${project_dir}." >&2
    exit 1
fi

cd "$project_dir"
echo "Starting pipeline stage: ${stage}."
exec "${command[@]}"
