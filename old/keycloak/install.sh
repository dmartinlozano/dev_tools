#!/bin/bash
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

echo "   ▪ Checking if keycloak is already installed..."
if helm list -n dev-tools | grep -q "keycloak"; then
  echo "   ▪ Keycloak is already installed. Skipping installation."
  exit 0
fi

VAULT_ROOT_TOKEN=$(cat "$SCRIPT_DIR/../vault/.tmp-vault-root-token")
if [ -z "$VAULT_ROOT_TOKEN" ]; then
  echo "❌  Could not get Vault root token. Checking if Vault is installed..."
  run kubectl get pods -n dev-tools | grep vault
  exit 1
fi

"$SCRIPT_DIR/../postgresql/create-database.sh" "keycloak"
if [ $? -ne 0 ]; then
  echo "❌  Error: Failed to create Keycloak database."
  exit 1
fi

BASE_DNS=$(get_secret_literal "base-dns")
export KEYCLOAK_HOSTNAME="keycloak.$BASE_DNS"

# Get user and password from Vault created when database was created
DB_USER=$("$SCRIPT_DIR/../vault/get-credentials.sh" "postgresql/keycloak" "username")
DB_PASSWORD=$("$SCRIPT_DIR/../vault/get-credentials.sh" "postgresql/keycloak" "password")
if [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
  echo "❌  Error: Could not retrieve database credentials from Vault"
  exit 1
fi

# Install Keycloak

echo "   ▪ Installing keycloak..."

ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)
envsubst < values.yaml > .values.yaml.rendered
run helm upgrade --install keycloak bitnami/keycloak \
  --namespace dev-tools \
  -f .values.yaml.rendered \
  --set externalDatabase.user=$DB_USER \
  --set externalDatabase.password=$DB_PASSWORD \
  --set auth.adminPassword=$ADMIN_PASSWORD

rm -rf .values.yaml.rendered

wait_for_service_ready keycloak

# Store credentials in Vault
chmod +x "$SCRIPT_DIR/../vault/create-credentials.sh"
"$SCRIPT_DIR/../vault/create-credentials.sh" "keycloak/admin" "admin" "$ADMIN_PASSWORD"

# Keycloak init
chmod +x "$SCRIPT_DIR/initialize.sh"
run_script_as_job "$SCRIPT_DIR/initialize.sh" "$ADMIN_PASSWORD"
if [ $? -ne 0 ]; then
  echo "❌  Error: Failed to initialize Keycloak."
  exit 1
fi

echo "   ▪ Keycloak installation completed successfully."