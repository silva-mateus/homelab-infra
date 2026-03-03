#!/bin/bash
# Each project gets a dedicated user with access only to its own database.
# Passwords come from environment variables defined in docker-compose.

set -e

create_user_and_grant() {
    local db_user="$1"
    local db_password="$2"
    local db_name="$3"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        CREATE USER ${db_user} WITH PASSWORD '${db_password}';
        GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
EOSQL

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "${db_name}" <<-EOSQL
        GRANT ALL ON SCHEMA public TO ${db_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${db_user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${db_user};
EOSQL
}

create_user_and_grant "$MUSICAS_DB_USER" "$MUSICAS_DB_PASSWORD" "musicas_igreja"
create_user_and_grant "$PASTORAL_DB_USER" "$PASTORAL_DB_PASSWORD" "gerenciamento_pastoral"
create_user_and_grant "$FINANCEIRO_DB_USER" "$FINANCEIRO_DB_PASSWORD" "gerenciamento_financeiro"
