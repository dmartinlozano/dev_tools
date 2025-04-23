#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ./utils.sh

# Ensure dev-tools namespace exists
if ! kubectl get namespace dev-tools >/dev/null 2>&1; then
  run kubectl create namespace dev-tools
fi

#configuration
if [ -z "$ENV" ] || [ "$ENV" = "dev" ]; then
  ENV=dev
  save_secret_literal "base-dns" $(get-dns)
else
  save_secret_literal "admin-email" "$ADMIN_EMAIL"
  save_secret_literal "base-dns" "$BASE_DNS"
fi

save_secret_literal "env" "$ENV"

if [ -z "$DASHBOARD_CN" ]; then
  DASHBOARD_CN="devtools"
fi
save_secret_literal "dashboard-cn" "$DASHBOARD_CN"

echo "🔧 Installing certificates & ingress..."
chmod +x "$SCRIPT_DIR/certificates/install.sh"
chmod +x "$SCRIPT_DIR/ingress/install.sh"
"$SCRIPT_DIR/certificates/install.sh" || exit 1
"$SCRIPT_DIR/ingress/install.sh" || exit 1

if [ "$ENV" = "dev" ]; then
  echo "🔒 Installing vault"
  chmod +x "$SCRIPT_DIR/vault/install.sh"
  "$SCRIPT_DIR/vault/install.sh" || exit 1
fi

echo "🐘 Installing PostgreSQL"
chmod +x "$SCRIPT_DIR/postgresql/install.sh"
"$SCRIPT_DIR/postgresql/install.sh" || exit 1

# Install Keycloak
echo "🔑 Installing Keycloak"
chmod +x "$SCRIPT_DIR/keycloak/install.sh"
"$SCRIPT_DIR/keycloak/install.sh" || exit 1

# Install Dashboard Frontend
echo "📊 Installing Dashboard"

chmod +x "$SCRIPT_DIR/dashboard-backend/install.sh"
"$SCRIPT_DIR/dashboard-backend/install.sh" || exit 1

chmod +x "$SCRIPT_DIR/dashboard-frontend/install.sh"
"$SCRIPT_DIR/dashboard-frontend/install.sh" || exit 1

# Run cronjob to renew certificates
echo "🕒 Installing cronjob to renew certificates"
export SERVICES=$(kubectl get svc -n dev-tools -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' | tr ' ' '\n' | cut -d- -f1 | sort -u | tr '\n' ' ' | sed 's/ *$//')
export BASE_DNS=$(kubectl get secret base-dns -n dev-tools -o jsonpath='{.data.base-dns}' | base64 --decode)

envsubst < "$SCRIPT_DIR/certificates/values/renew-certs-cronjob.yaml" > "$SCRIPT_DIR/certificates/values/renew-certs-cronjob.yaml.rendered"
run kubectl apply -f "$SCRIPT_DIR/certificates/values/renew-certs-cronjob.yaml.rendered"
rm -rf "$SCRIPT_DIR/certificates/values/renew-certs-cronjob.yaml.rendered"

# Delete secrets
if kubectl get secret keycloak -n dev-tools >/dev/null 2>&1; then
  run kubectl delete secret -n dev-tools keycloak
fi
if kubectl get secret keycloak-externaldb -n dev-tools >/dev/null 2>&1; then
  run kubectl delete secret -n dev-tools keycloak-externaldb
fi
if kubectl get secret dev-tools-tls-keycloak -n dev-tools >/dev/null 2>&1; then
  run kubectl delete secret -n dev-tools dev-tools-tls-keycloak
fi

DASHBOARD_HOSTNAME=$(get_secret_literal "dashboard-hostname")
ADMIN_PASSWORD=$("$SCRIPT_DIR/vault/get-credentials.sh" "keycloak/admin" "password")
echo "👀 Url access: https://$DASHBOARD_HOSTNAME with user 'admin' and password '$ADMIN_PASSWORD'"
echo "👀 Vault token generated: '$(cat vault/.tmp-vault-root-token)' Please store it safely."

echo "🎉 Environment ready!"