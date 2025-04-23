#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

RELEASE="dashboard-frontend"
IMAGE="$RELEASE:local"

# Enable Docker env for Minikube if minikube exists
if command -v minikube &>/dev/null; then
  if ! minikube status &>/dev/null; then
    echo "❌ Minikube is not running. Please start it first."
    exit 1
  fi
  echo "   ▪ Setting Docker environment to Minikube..."
  eval $(minikube docker-env)
fi

echo "   ▪ Building Docker image for dashboard-frontend..."
run docker build -t $IMAGE .

BASE_DNS=$(get_secret_literal "base-dns")
DASHBOARD_CN=$(get_secret_literal "dashboard-cn")

echo "   ▪ Installing/Upgrading Helm release..."

envsubst < "$SCRIPT_DIR/charts/values.yaml" > "$SCRIPT_DIR/charts/.values.yaml.rendered"

run helm upgrade --install $RELEASE $SCRIPT_DIR/charts \
  --namespace dev-tools \
  -f "$SCRIPT_DIR/charts/.values.yaml.rendered" \
  --set image.repository=$IMAGE \
  --set DASHBOARD_CN=$DASHBOARD_CN \
  --set DASHBOARD_HOSTNAME="$DASHBOARD_CN.$BASE_DNS"

rm -rf "$SCRIPT_DIR/charts/.values.yaml.rendered"