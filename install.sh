#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create namespace dev-tools
if ! kubectl get namespace dev-tools >/dev/null 2>&1; then
    kubectl create namespace dev-tools
fi

# Install Dashboard Frontend
echo "📊 Installing Dashboard"

chmod +x "$SCRIPT_DIR/dashboard-installer/install.sh"
"$SCRIPT_DIR/dashboard-installer/install.sh" || exit 1