#!/bin/bash

BASE_DNS="$1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Initialize vault
INIT_STATUS=$(kubectl exec -n dev-tools vault-0 -- vault status -format=json 2>/dev/null || echo '{}')
IS_INITIALIZED=$(echo "$INIT_STATUS" | grep -o '"initialized":\(true\|false\)' | cut -d':' -f2 | tr -d '"')
if [ "$IS_INITIALIZED" != "true" ]; then
  echo "    Initializing primary Vault..."
  INIT_OUTPUT=$(kubectl exec -n dev-tools vault-0 -- vault operator init -format=json)
  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep -o '"root_token":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')
  UNSEAL_KEYS_B64=$(echo "$INIT_OUTPUT" | grep -o '"unseal_keys_b64":\[[^\]]*\]' | sed 's/.*\[\(.*\)\].*/\1/' | tr -d '"' | tr ',' '\n')
  kubectl create secret generic vault-token --from-literal=key=$ROOT_TOKEN -n dev-tools
  for i in {1..10}; do
    kubectl get secret vault-token -n dev-tools >/dev/null 2>&1 && break
    sleep 1
  done
  kubectl create secret generic vault-unseal-keys --from-literal=unseal_keys_b64="$UNSEAL_KEYS_B64" -n dev-tools
  for i in {1..10}; do
    kubectl get secret vault-unseal-keys -n dev-tools >/dev/null 2>&1 && break
    sleep 1
  done
  i=0
  for KEY in $UNSEAL_KEYS_B64; do
    if [ $i -ge 3 ]; then break; fi
    kubectl exec -n dev-tools vault-0 -- vault operator unseal $KEY
    i=$((i+1))
  done
else
  echo "    Vault already initialized, retrieving root token..."
  ROOT_TOKEN=$(kubectl get secret vault-token -n dev-tools -o jsonpath='{.data.key}' 2>/dev/null | base64 --decode)
  if [ -z "$ROOT_TOKEN" ]; then
    echo "❌ Error: No se pudo obtener el token de root de Vault desde el secreto. Por favor, verifica que el secreto 'vault-token' existe."
    exit 1
  fi
  echo "    Root token retrieved successfully."

  # When vault is already initialized, retrieve unseal keys as a JSON array for Python compatibility
  UNSEAL_KEYS_B64_JSON=$(kubectl get secret vault-unseal-keys -n dev-tools -o jsonpath='{.data.unseal_keys_b64}' 2>/dev/null | base64 --decode)
  # If the value is not a valid JSON array, convert it
  if ! echo "$UNSEAL_KEYS_B64_JSON" | grep -q '^\['; then
    # Convert space/newline separated keys to JSON array
    UNSEAL_KEYS_B64_JSON=$(echo "$UNSEAL_KEYS_B64_JSON" | awk '{printf "["; for(i=1;i<=NF;i++){printf "\"%s\"", $i; if(i<NF){printf ","}}; print "]"}')
  fi
  # Overwrite the secret with the JSON array for Python compatibility
  kubectl create secret generic vault-unseal-keys --from-literal=unseal_keys_b64="$UNSEAL_KEYS_B64_JSON" -n dev-tools --dry-run=client -o yaml | kubectl apply -f -
  # Store as secret for Python
  export UNSEAL_KEYS_B64_JSON
fi

if [ -z "$ROOT_TOKEN" ]; then
  echo "❌ Error: No se pudo obtener el token de root de Vault."
  exit 1
fi

# Check if PKI is enabled for certificates
PKI_ENABLED=$(kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets list" | grep -q '^pki/'; echo $?)
if [ "$PKI_ENABLED" -ne 0 ]; then
  echo "    Enabling PKI for certificates"
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable pki"
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets tune -max-lease-ttl=2400h pki"
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write -field=certificate pki/root/generate/internal common_name=\"$BASE_DNS\" ttl=2400h"
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write pki/config/urls issuing_certificates=\"http://vault-0.dev-tools.svc.cluster.local:8200/v1/pki/ca\" crl_distribution_points=\"http://vault-0.dev-tools.svc.cluster.local:8200/v1/pki/crl\""
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write pki/roles/dev-tools \
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

echo "    Enabling transit engine and creating unseal key"
if ! kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets list -format=json" | grep -q '"transit/":'; then
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets enable -path=transit transit"
fi

kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write -f transit/keys/vault-unseal-key"

echo "    Creating policy and token for transit auto-unseal"
kubectl cp "$SCRIPT_DIR/policies/vault-policy.hcl" dev-tools/vault-0:/tmp/transit-unseal-policy.hcl
kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault policy write transit-unseal /tmp/transit-unseal-policy.hcl"
TRANSIT_TOKEN=$(kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault token create -policy=transit-unseal -format=json" | jq -r .auth.client_token)

echo "    Creating Secret for transit token"
kubectl create secret generic vault-transit-token --from-literal=token="$TRANSIT_TOKEN" -n dev-tools --dry-run=client -o yaml | kubectl apply -f -

# Enable and configure Kubernetes authentication
if ! kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault auth list | grep -q 'kubernetes/'; then
  echo "    Enabling Kubernetes auth method"
  kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault auth enable kubernetes"
fi

# Configure Kubernetes authentication method
KUBE_HOST=$(kubectl exec -n dev-tools vault-0 -- sh -c 'echo $KUBERNETES_PORT_443_TCP_ADDR' || echo "kubernetes.default.svc")
kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write auth/kubernetes/config \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token \
  kubernetes_host=https://$KUBE_HOST:443 \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

# Copy and apply the minimum policy before creating the dev-tools role
kubectl cp "$SCRIPT_DIR/policies/service-policy.hcl" dev-tools/vault-0:/tmp/service-policy.hcl
kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault policy write service-policy /tmp/service-policy.hcl"
kubectl cp "$SCRIPT_DIR/policies/vault-policy.hcl" dev-tools/vault-0:/tmp/pki-admin.hcl
kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault policy write pki-admin /tmp/pki-admin.hcl"

kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault write auth/kubernetes/role/dev-tools \
  bound_service_account_names=dev-tools-sa,cert-manager \
  bound_service_account_namespaces=dev-tools \
  policies=default,pki-admin,service-policy \
  ttl=2160h"

echo "    Installing secondary Vault (auto-unseal with transit)"
helm upgrade -install vault-kms hashicorp/vault --namespace dev-tools -f "$SCRIPT_DIR/values/values-kms.yaml"

echo "    Waiting for secondary Vault pod to be ready"
while [[ $(kubectl get pod -n dev-tools -l app.kubernetes.io/instance=vault-kms -o jsonpath='{.items[0].status.phase}') != "Running" ]]; do sleep 5; done
sleep 10

# Check if the 'secret/' path is enabled and if it is kv-v2
SECRET_MOUNT_INFO=$(kubectl exec -n dev-tools vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault secrets list -detailed" | awk '/^secret\//{flag=1} flag; /^$/{flag=0}' | head -n 10)
SECRET_VERSION=$(echo "$SECRET_MOUNT_INFO" | grep 'version:' | awk '{print $2}')

if [ -z "$SECRET_MOUNT_INFO" ]; then
  # Path does not exist, enable as kv-v2
  kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2
elif [ "$SECRET_VERSION" != "2" ]; then
  echo "    The path 'secret/' is enabled but not kv-v2. It will be disabled and re-enabled as kv-v2 (this deletes data under secret/!)."
  kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets disable secret
  kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2
else
  echo "    The path 'secret/' is already enabled as kv-v2."
fi

echo "    Both Vaults installed and connected successfully."
