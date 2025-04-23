#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/../utils.sh"

# Print value if found, else print warning
VAULT_PATH="$1"
FIELD="$2"

VAULT_ROOT_TOKEN=$(cat "$SCRIPT_DIR/../vault/.tmp-vault-root-token")
VALUE=$(kubectl exec -n dev-tools vault-0 -- env VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault kv get -field="$FIELD" secret/dev-tools/$VAULT_PATH)
if [ -n "$VALUE" ]; then
  echo "$VALUE"
  exit 0
fi

echo "⚠️  Could not read field $FIELD for $VAULT_PATH" >&2
exit 1
