#!/usr/bin/env bash
set -Eeuo pipefail

required_variables=(
    POSTGRES_USER
    POSTGRES_DB
    DB_USER
    DB_PASSWORD
    OLTP_USER
    OLTP_PASSWORD
)

for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
        echo "Required environment variable ${variable_name} is not set." >&2
        exit 1
    fi
done

if [[ "$DB_USER" == "$POSTGRES_USER" || "$OLTP_USER" == "$POSTGRES_USER" ]]; then
    echo "Application roles must be different from POSTGRES_USER." >&2
    exit 1
fi

if [[ "$DB_USER" == "$OLTP_USER" ]]; then
    echo "DB_USER and OLTP_USER must use separate PostgreSQL roles." >&2
    exit 1
fi

psql_command=(
    psql
    --variable=ON_ERROR_STOP=1
    --username "$POSTGRES_USER"
    --dbname "$POSTGRES_DB"
)

create_login_role() {
    local role_name="$1"
    local role_password="$2"

    "${psql_command[@]}" \
        --set=role_name="$role_name" \
        --set=role_password="$role_password" <<'SQL'
SELECT format(
    'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
    :'role_name',
    :'role_password'
)
WHERE NOT EXISTS (
    SELECT 1
    FROM pg_roles
    WHERE rolname = :'role_name'
)
\gexec

SELECT format(
    'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
    :'role_name',
    :'role_password'
)
\gexec
SQL
}

echo "Creating least-privilege PostgreSQL roles..."
create_login_role "$DB_USER" "$DB_PASSWORD"
create_login_role "$OLTP_USER" "$OLTP_PASSWORD"

ddl_files=(
    /ddl/oltp.sql
    /ddl/datavault.sql
    /ddl/fact_constelation.sql
    /ddl/etl.sql
)

for ddl_file in "${ddl_files[@]}"; do
    if [[ ! -r "$ddl_file" ]]; then
        echo "Required DDL file ${ddl_file} is not readable." >&2
        exit 1
    fi

    echo "Applying ${ddl_file}..."
    "${psql_command[@]}" --file "$ddl_file"
done

echo "Applying role ownership and grants..."
"${psql_command[@]}" \
    --set=database_name="$POSTGRES_DB" \
    --set=etl_user="$DB_USER" \
    --set=oltp_user="$OLTP_USER" <<'SQL'
GRANT CONNECT ON DATABASE :"database_name" TO :"etl_user", :"oltp_user";

GRANT USAGE ON SCHEMA oltp TO :"etl_user", :"oltp_user";
GRANT SELECT ON ALL TABLES IN SCHEMA oltp TO :"etl_user";
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA oltp TO :"oltp_user";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA oltp TO :"oltp_user";

GRANT USAGE ON SCHEMA data_vault, galaxy TO :"etl_user";
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA data_vault, galaxy TO :"etl_user";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA data_vault, galaxy TO :"etl_user";

ALTER SCHEMA etl OWNER TO :"etl_user";
ALTER TABLE etl.etl_control OWNER TO :"etl_user";

SELECT format(
    'ALTER SEQUENCE %I.%I OWNER TO %I',
    sequence_schema,
    sequence_name,
    :'etl_user'
)
FROM information_schema.sequences
WHERE sequence_schema = 'etl'
\gexec

ALTER DEFAULT PRIVILEGES IN SCHEMA oltp
    GRANT SELECT ON TABLES TO :"etl_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA oltp
    GRANT SELECT, INSERT ON TABLES TO :"oltp_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA oltp
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"oltp_user";

ALTER DEFAULT PRIVILEGES IN SCHEMA data_vault, galaxy
    GRANT SELECT, INSERT, UPDATE ON TABLES TO :"etl_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA data_vault, galaxy
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"etl_user";
SQL

echo "PostgreSQL bootstrap completed successfully."
