#!/bin/bash
set -e

TOOL="$1"
KEYCLOAK_HOSTNAME="https://127.0.01:8443"
VAULT_HOSTNAME="https://vault.dev-tools.svc:8200"

echo "🔐 Initializing Keycloak with required configurations..."

echo "    Waiting for Keycloak to be available..."
KEYCLOAK_AVAILABLE=false
MAX_ATTEMPTS=30
ATTEMPTS=0

while [ "$KEYCLOAK_AVAILABLE" = false ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    RESPONSE=$(curl -s -k --connect-timeout 5 ${KEYCLOAK_HOSTNAME}/realms/master)
    echo "Try $((ATTEMPTS+1)): $RESPONSE"
    if echo "$RESPONSE" | grep -q '"realm":"master"'; then
        KEYCLOAK_AVAILABLE=true
        break
    fi
    ATTEMPTS=$((ATTEMPTS+1))
    echo "    Keycloak is not available yet (attempt $ATTEMPTS/$MAX_ATTEMPTS). Waiting 10s..."
    sleep 10
done

if [ "$KEYCLOAK_AVAILABLE" = false ]; then
    echo "❌ Error: Keycloak is not available after $MAX_ATTEMPTS attempts. Please check your Keycloak deployment."
    exit 1
fi

echo "Fetching admin password from Vault..."
VAULT_TOKEN=$(kubectl get secret vault-token -n dev-tools -o jsonpath='{.data.key}' 2>/dev/null | base64 --decode)
ADMIN_PASSWORD=$(curl -s --header "X-Vault-Token: $VAULT_TOKEN" --request GET $VAULT_HOSTNAME/v1/secret/data/dev-tools/keycloak/admin | grep -o '"password":"[^"]*"' | head -n1 | sed 's/.*"password":"\([^"]*\)".*/\1/')
if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" == "null" ]; then
    echo "❌ Error: Could not retrieve admin password from Vault."
    exit 1
fi
echo "Admin password retrieved from Vault."

echo "    Authenticating with Keycloak Admin..."
echo "    Using admin password: ${ADMIN_PASSWORD}"
ADMIN_TOKEN=$(curl -k -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    "${KEYCLOAK_HOSTNAME}/realms/master/protocol/openid-connect/token" | grep -o '"access_token":"[^"]*"' | head -n1 | sed 's/.*"access_token":"\([^"]*\)".*/\1/')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo "❌ Error: Could not obtain a token for admin user. Please check credentials."
    exit 1
fi


echo "    Checking ${TOOL} client..."
CLIENT_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | grep -o '"clientId":"'"${TOOL}"'"' | head -n1)

if [ -z "$CLIENT_EXISTS" ]; then
    echo "    Creating $TOOL client..."
    RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": '${TOOL}',
            "protocol": "openid-connect",
            "publicClient": false,
            "standardFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "implicitFlowEnabled": false
        }' \
        "${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error creating client: $RESPONSE"
    else
        echo "    ${TOOL} client created successfully."
    fi
else
    echo "    ${TOOL} client already exists, updating configuration..."
    CLIENT_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | grep -o '{[^}]*"clientId":"'"${TOOL}"'"[^}]*}' | head -n1 | sed 's/.*"id":"\([^"]*\)".*/\1/')
    
    if [ -n "$CLIENT_ID" ]; then
        RESPONSE=$(curl -k -s -X PUT \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
                "clientId": '${TOOL}',
            "protocol": "openid-connect",
            "publicClient": false,
            "standardFlowEnabled": false,
            "directAccessGrantsEnabled": true,
            "serviceAccountsEnabled": false,
            "implicitFlowEnabled": false
            }' \
            "${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients/${CLIENT_ID}")
        
        if [[ "$RESPONSE" == *"error"* ]]; then
            echo "   ❌ Error updating client: $RESPONSE"
        else
            echo "    ${TOOL} client updated successfully."
        fi
    else
        echo "   ⚠️ Could not get ${TOOL} client ID for update"
    fi
fi

sleep 2

# Buscar el CLIENT_ID del cliente (usando $TOOL)
CLIENT_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | grep -o '{[^}]*"clientId":"'"${TOOL}"'"[^}]*}' | head -n1 | sed 's/.*"id":"\([^"]*\)".*/\1/')

if [ -n "$CLIENT_ID" ]; then
    CLIENT_SECRET=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients/${CLIENT_ID}/client-secret" | grep -o '"value":"[^"]*"' | head -n1 | sed 's/.*"value":"\([^"]*\)".*/\1/')
    echo "    ${TOOL} client secret: ${CLIENT_SECRET}"
else
    echo "   ⚠️ Could not get ${TOOL} client ID"
fi

echo "    Keycloak has been successfully initialized."