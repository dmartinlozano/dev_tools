#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

echo "    Checking if Wikijs is already installed..."
if helm list -n dev-tools | grep -q "wiki"; then
  echo "    Wiki.js is already installed. Skipping installation."
  exit 0
else
  run helm repo add requarks https://charts.js.wiki
fi

VAULT_ROOT_TOKEN=$(cat "$SCRIPT_DIR/../vault/.tmp-vault-root-token")
if [ -z "$VAULT_ROOT_TOKEN" ]; then
  echo "❌  Could not get Vault root token. Checking if Vault is installed..."
  run kubectl get pods -n dev-tools | grep vault
  exit 1
fi

"$SCRIPT_DIR/../postgresql/create-database.sh" "wiki"
if [ $? -ne 0 ]; then
  echo "❌  Error: Failed to create Wikijs database."
  exit 1
fi

BASE_DNS=$(get_secret_literal "base-dns")
export WIKI_HOSTNAME="wikijs.$BASE_DNS"

# Get user and password from Vault created when database was created
export DB_USER=$("$SCRIPT_DIR/../vault/get-credentials.sh" "postgresql/wiki" "username")
export DB_PASSWORD=$("$SCRIPT_DIR/../vault/get-credentials.sh" "postgresql/wiki" "password")
if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "❌  Error: Could not retrieve database credentials from Vault"
  exit 1
fi

echo "    Installing wiki.js..."

ENV=$(get_secret_literal "env")
if [[ "$ENV" == "dev" ]]; then
  NODE_TLS_REJECT_UNAUTHORIZED="0"
else
  NODE_TLS_REJECT_UNAUTHORIZED="1"
fi

envsubst < values.yaml > .values.yaml.rendered
run helm upgrade --install wiki requarks/wiki \
  --namespace dev-tools \
  -f .values.yaml.rendered \
  --set externalPostgresql.NODE_TLS_REJECT_UNAUTHORIZED=$NODE_TLS_REJECT_UNAUTHORIZED

rm -rf .values.yaml.rendered
wait_for_service_ready wiki

chmod +x "$SCRIPT_DIR/../vault/get-credentials.sh"
POSTGRES_PASSWORD=$("$SCRIPT_DIR/../vault/get-credentials.sh" "postgresql/admin" "password")
KEYCLOAK_ADMIN_PASSWORD=$("$SCRIPT_DIR/../vault/get-credentials.sh" "keycloak/admin" "password")

chmod +x "$SCRIPT_DIR/initialize.sh"
run_script_as_job "$SCRIPT_DIR/initialize.sh" $POSTGRES_PASSWORD $KEYCLOAK_ADMIN_PASSWORD
if [ $? -ne 0 ]; then
  echo "❌  Error: Failed to initialize Wiki.js."
  exit 1
fi

echo "    Wiki.js installation completed successfully."