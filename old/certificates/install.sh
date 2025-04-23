#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

# Create service account dev-tools-sa if it does not exist
if ! kubectl get serviceaccount dev-tools-sa -n dev-tools >/dev/null 2>&1; then
  run kubectl create serviceaccount dev-tools-sa -n dev-tools
  run kubectl create clusterrolebinding dev-tools-sa-token-creator \
  --clusterrole=system:service-account-token-creator \
  --serviceaccount=dev-tools:dev-tools-sa
fi

# Install cert-manager using Helm
echo "   ▪ Installing cert-manager..."
if ! kubectl get deployment -n cert-manager cert-manager &>/dev/null; then

  run helm repo add jetstack https://charts.jetstack.io --force-update
  run helm repo update
  run helm upgrade --install \
    cert-manager jetstack/cert-manager \
    --namespace dev-tools \
    --create-namespace \
    --version v1.13.0 \
    --set installCRDs=true

  # Wait for cert-manager to be ready
  run kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n dev-tools
  run kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-webhook -n dev-tools
  run kubectl wait --for=condition=available --timeout=300s deployment/cert-manager-cainjector -n dev-tools
  echo "   ▪ cert-manager is ready."
else
  echo "   ▪ cert-manager is already installed, skipping installation..."
fi

echo "   ▪ Applying TLS certificate configuration..."

run kubectl apply -f $SCRIPT_DIR/values/roles.yaml

ENV=$(get_secret_literal "env")
if [[ "$ENV" == "dev" ]]; then
  run kubectl apply -f "$SCRIPT_DIR/values/vault.yaml"
else
  envsubst < $SCRIPT_DIR/values/letsencrypt.yaml | kubectl apply -f -
fi

envsubst < $SCRIPT_DIR/values/ingress.yaml | kubectl apply -f -

echo "   ▪ TLS configuration applied successfully."