#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

ENV=$(get_secret_literal "env")

echo "   ▪ Adding Hashicorp Helm repo if missing and updating"
if ! helm repo list | grep -q "^hashicorp"; then
  run helm repo add hashicorp https://charts.hashicorp.com
fi

echo "   ▪ Installing primary Vault (KMS)"
run helm upgrade --install vault hashicorp/vault --namespace dev-tools -f "$SCRIPT_DIR/values.yaml"

echo "   ▪ Waiting for primary Vault pod to be ready"
wait_for_service_running vault

INIT_STATUS=$(kubectl exec -n dev-tools vault-0 -- vault status -format=json 2>/dev/null || echo '{}')
IS_INITIALIZED=$(echo "$INIT_STATUS" | jq -r '.initialized')
if [ "$IS_INITIALIZED" != "true" ]; then
  echo "   ▪ Initializing primary Vault..."
  INIT_OUTPUT=$(kubectl exec -n dev-tools vault-0 -- vault operator init -format=json)
  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
  echo "$ROOT_TOKEN" > .tmp-vault-root-token
  for i in $(seq 0 2); do
    KEY=$(echo "$INIT_OUTPUT" | jq -r ".unseal_keys_b64[$i]")
    run kubectl exec -n dev-tools vault-0 -- vault operator unseal $KEY
  done
else
  echo "   ▪ Vault is already initialized."
  ROOT_TOKEN=$(cat ".tmp-vault-root-token")
  exit 0
fi

if [ -z "$ROOT_TOKEN" ]; then
  echo "❌ ROOT_TOKEN is empty. Aborting."
  exit 1
fi

# Check if PKI is enabled for certificates
PKI_ENABLED=$(kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets list" | grep -q '^pki/'; echo $?)
if [ "$ENV" == "dev" ] && [ "$PKI_ENABLED" -ne 0 ]; then
  echo "   ▪ Enabling PKI for certificates"
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable pki"
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets tune -max-lease-ttl=2400h pki"
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write -field=certificate pki/root/generate/internal common_name=\"$BASE_DNS\" ttl=2400h"
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write pki/config/urls issuing_certificates=\"http://vault-0.dev-tools.svc.cluster.local:8200/v1/pki/ca\" crl_distribution_points=\"http://vault-0.dev-tools.svc.cluster.local:8200/v1/pki/crl\""
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write pki/roles/dev-tools \
    allowed_domains=\"$BASE_DNS\" \
    allow_subdomains=true \
    allow_glob_domains=true \
    allow_any_name=true \
    max_ttl=2400h \
    bound_service_account_names=dev-tools-sa \
    bound_service_account_namespaces=dev-tools \
    policies=default,pki-admin,service-policy \
    ttl=2160h"
fi

echo "   ▪ Enabling transit engine and creating unseal key"
if ! kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets list -format=json" | grep -q '"transit/":'; then
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=transit transit"
fi

run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write -f transit/keys/vault-unseal-key"

echo "   ▪ Creating policy and token for transit auto-unseal"
run kubectl cp "$SCRIPT_DIR/vault-policy.hcl" dev-tools/vault-0:/tmp/transit-unseal-policy.hcl
run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault policy write transit-unseal /tmp/transit-unseal-policy.hcl"
TRANSIT_TOKEN=$(kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=transit-unseal -format=json" | jq -r .auth.client_token)

echo "   ▪ Creating Secret for transit token"
kubectl create secret generic vault-transit-token --from-literal=token="$TRANSIT_TOKEN" -n dev-tools --dry-run=client -o yaml | kubectl apply -f -

# Enable and configure Kubernetes authentication
if ! kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault auth list | grep -q 'kubernetes/'; then
  echo "   ▪ Enabling Kubernetes auth method"
  run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault auth enable kubernetes"
fi

# Configure Kubernetes authentication method
KUBE_HOST=$(kubectl exec -n dev-tools vault-0 -- sh -c 'echo $KUBERNETES_PORT_443_TCP_ADDR' || echo "kubernetes.default.svc")
run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write auth/kubernetes/config \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token \
  kubernetes_host=https://$KUBE_HOST:443 \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

# Copy and apply the minimum policy before creating the dev-tools role
run kubectl cp "$SCRIPT_DIR/service-policy.hcl" dev-tools/vault-0:/tmp/service-policy.hcl
run kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault policy write service-policy /tmp/service-policy.hcl
run kubectl cp "$SCRIPT_DIR/vault-policy.hcl" dev-tools/vault-0:/tmp/pki-admin.hcl
run kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault policy write pki-admin /tmp/pki-admin.hcl

run kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write auth/kubernetes/role/dev-tools \
  bound_service_account_names=dev-tools-sa,cert-manager \
  bound_service_account_namespaces=dev-tools \
  policies=default,pki-admin,service-policy \
  ttl=2160h"

echo "   ▪ Installing secondary Vault (auto-unseal with transit)"
run helm upgrade -install vault-kms hashicorp/vault --namespace dev-tools -f "$SCRIPT_DIR/values-kms.yaml"

echo "   ▪ Waiting for secondary Vault pod to be ready"
while [[ $(kubectl get pod -n dev-tools -l app.kubernetes.io/instance=vault-kms -o jsonpath='{.items[0].status.phase}') != "Running" ]]; do sleep 5; done
sleep 10

# Check if the 'secret/' path is enabled and if it is kv-v2
SECRET_MOUNT_INFO=$(kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets list -detailed" | awk '/^secret\//{flag=1} flag; /^$/{flag=0}' | head -n 10)
SECRET_VERSION=$(echo "$SECRET_MOUNT_INFO" | grep 'version:' | awk '{print $2}')

if [ -z "$SECRET_MOUNT_INFO" ]; then
  # Path does not exist, enable as kv-v2
  run kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2
elif [ "$SECRET_VERSION" != "2" ]; then
  echo "   ▪ The path 'secret/' is enabled but not kv-v2. It will be disabled and re-enabled as kv-v2 (this deletes data under secret/!)."
  run kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets disable secret
  run kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2
else
  echo "   ▪ The path 'secret/' is already enabled as kv-v2."
fi

echo "   ▪ Both Vaults installed and connected successfully."
