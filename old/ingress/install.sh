#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

run helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
run helm repo update

run helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace dev-tools \
  -f values.yaml