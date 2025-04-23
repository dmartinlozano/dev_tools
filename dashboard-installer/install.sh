#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RELEASE="dashboard-installer"
IMAGE="dashboard-installer:local"

# Enable Docker env for Minikube if minikube exists
if command -v minikube &>/dev/null; then
  if ! minikube status &>/dev/null; then
    echo "❌ Minikube is not running. Please start it first."
    exit 1
  fi
  echo "   ▪ Setting Docker environment to Minikube..."
  eval $(minikube docker-env)
fi

echo "   ▪ Building Docker image for dashboard-installer..."
docker build -t $IMAGE .

echo "   ▪ Installing/Upgrading Helm release..."

helm upgrade --install $RELEASE $SCRIPT_DIR/charts \
  --namespace dev-tools \
  -f "$SCRIPT_DIR/charts/values.yaml" \
  --set image.repository=$IMAGE
