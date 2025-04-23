#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../utils.sh"

echo "   ▪ Adding the Bitnami Helm repository..."
run helm repo add bitnami https://charts.bitnami.com/bitnami
run helm repo update

echo "   ▪ Checking if PostgreSQL is already installed..."
if helm list -n dev-tools | grep -q "postgresql"; then
  echo "   ▪ PostgreSQL is already installed. Skipping installation."
  exit 0
fi

VAULT_ROOT_TOKEN=$(cat "$SCRIPT_DIR/../vault/.tmp-vault-root-token")
if [ -z "$VAULT_ROOT_TOKEN" ]; then
  echo "❌  Could not get Vault root token. Checking if Vault is installed..."
  run kubectl get pods -n dev-tools | grep vault
  exit 1
fi

POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20)

run helm upgrade --install postgresql bitnami/postgresql \
  --namespace dev-tools \
  -f "$SCRIPT_DIR/values.yaml" \
  --set auth.postgresPassword="$POSTGRES_PASSWORD"

echo "   ▪ Waiting for PostgreSQL to be ready..."
wait_for_service_ready postgresql

#Store credentials in Vault
chmod +x "$SCRIPT_DIR/../vault/create-credentials.sh"
"$SCRIPT_DIR/../vault/create-credentials.sh" "postgresql/admin" "postgres" "$POSTGRES_PASSWORD"
echo "   ▪ Check connection..."
if kubectl exec -n dev-tools postgresql-0 -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c '\du'" > /dev/null 2>&1; then
  echo "   ▪ Connection as postgres superuser works."
else
  echo "❌  Could not connect as postgres superuser."
  echo "👀  Showing PostgreSQL container logs for diagnostics:"
  run kubectl logs -n dev-tools postgresql-0
fi
echo "   ▪ PostgreSQL installed and configured successfully."