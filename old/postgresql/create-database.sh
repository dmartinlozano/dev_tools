#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../utils.sh"

echo "   ▪ Creating database $1..."

DB_NAME=$1
USERNAME=$(openssl rand -hex 4)  
PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)

#PostgreSQL credentials
chmod +x "$SCRIPT_DIR/../vault/get-credentials.sh"
POSTGRES_PASSWORD=$("$SCRIPT_DIR/../vault/get-credentials.sh" "postgresql/admin" "password")

VAULT_ROOT_TOKEN=$(cat "$SCRIPT_DIR/../vault/.tmp-vault-root-token")
if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "❌  Error: Could not retrieve PostgreSQL admin password"
  exit 1
fi

EXISTS=$(kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -tc \"SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';\"")
if [[ ! "$EXISTS" =~ 1 ]]; then
  run kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -c \"CREATE DATABASE \\\"$DB_NAME\\\" ENCODING 'UTF8';\""
fi

run kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -c \"CREATE USER \\\"$USERNAME\\\" WITH ENCRYPTED PASSWORD '$PASSWORD';\""
run kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -c \"GRANT ALL PRIVILEGES ON DATABASE \\\"$DB_NAME\\\" TO \\\"$USERNAME\\\";\""
run kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -c \"GRANT USAGE ON SCHEMA public TO \\\"$USERNAME\\\";\" -d \"$DB_NAME\""
run kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -c \"GRANT CREATE ON SCHEMA public TO \\\"$USERNAME\\\";\" -d \"$DB_NAME\""

chmod +x "$SCRIPT_DIR/../vault/create-credentials.sh"
"$SCRIPT_DIR/../vault/create-credentials.sh" "postgresql/$DB_NAME" "$USERNAME" "$PASSWORD"

echo "   ▪ Database '$DB_NAME' created successfully."