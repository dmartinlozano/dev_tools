#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

run helm repo add bitnami https://charts.bitnami.com/bitnami
run helm repo update

run helm upgrade --install redis bitnami/redis \
  --namespace dev-tools \
  -f $VALUES_FILE