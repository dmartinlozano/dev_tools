#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

# Print error if credentials could not be saved
VAULT_PATH="$1"
USERNAME="$2"
PASSWORD="$3"
VAULT_ROOT_TOKEN=$(cat "$SCRIPT_DIR/../vault/.tmp-vault-root-token")

run kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault kv put secret/dev-tools/$VAULT_PATH username="$USERNAME" password="$PASSWORD"
RESULT=$?
if [ $RESULT -ne 0 ]; then
  echo "❌ Error saving credentials." >&2
  exit 1
fi