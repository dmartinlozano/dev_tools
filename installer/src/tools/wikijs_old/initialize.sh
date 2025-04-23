#!/bin/bash
set -e

# This script is running only in a job inside the dev-tools namespace
apt-get update && apt-get install -y curl jq

POSTGRES_PASSWORD="$1"
KEYCLOAK_ADMIN_PASSWORD="$2"
KEYCLOAK_HOSTNAME="keycloak.dev-tools.svc.cluster.local"

echo "    Adding client secret to Keycloak client using API..."

# Use admin-cli as client_id for initial authentication
ADMIN_TOKEN=$(curl -k -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    "https://${KEYCLOAK_HOSTNAME}/realms/master/protocol/openid-connect/token" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo "❌ Error: Failed to authenticate with Keycloak."
    exit 1
fi

# Verify if wikijs client already exists, if not, create it
echo "    Checking if wikijs client exists..."
CLIENT_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "wikijs") | .clientId')

if [ -z "$CLIENT_EXISTS" ]; then
    echo "    Creating wikijs client..."
    RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "wikijs",
            "protocol": "openid-connect",
            "enabled": true,
            "clientAuthenticatorType": "client-secret",
            "redirectUris": ["*"],
            "webOrigins": ["*"],
            "standardFlowEnabled": true,
            "implicitFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "publicClient": false
        }' \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "❌ Error creating wikijs client: $RESPONSE"
        exit 1
    fi
fi

CLIENT_ID=$(curl -k -s -X GET \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "wikijs") | .id')

if [ -z "$CLIENT_ID" ]; then
    echo "❌ Error: Wiki.js client not found in Keycloak."
    exit 1
fi

RESPONSE=$(curl -k -s -X POST \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"type": "client-secret"}' \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients/${CLIENT_ID}/client-secret")

CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.value')

if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
    echo "❌ Error: Failed to retrieve client secret for Wiki.js."
    exit 1
fi

LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 40

echo "    Configure Wiki.js with Keycloak..."

run kubectl exec -n dev-tools postgresql-0 -c postgresql -- bash -c "PGPASSWORD='$POSTGRES_PASSWORD' psql -U 'postgres' -c \"
INSERT INTO auth_strategies (
  id, enabled, name, strategy, config, auto_register, created_at, updated_at
)
VALUES (
  gen_random_uuid(),
  true,
  'Keycloak',
  'oidc',
  '{
    \"clientId\": \"wikijs\",
    \"clientSecret\": \"${CLIENT_SECRET}\",
    \"issuer\": \"https://keycloak.dev-tools.svc.cluster.local/realms/dev-tools\",
    \"scopes\": [\"openid\", \"email\", \"profile\"],
    \"callbackUrl\": \"https://wiki.dev-tools.svc.cluster.local/auth/oidc.callback\",
    \"userIdClaim\": \"sub\",
    \"usernameClaim\": \"preferred_username\",
    \"emailClaim\": \"email\",
    \"nameClaim\": \"name\",
    \"groupsClaim\": \"groups\"
  }',
  true,
  NOW(),
  NOW()
);\""

echo "    Successfully added client secret to Keycloak client. Secret: ${CLIENT_SECRET}"
