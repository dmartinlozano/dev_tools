#!/bin/bash
set -e

ADMIN_PASSWORD="$1"
CLIENT_HOSTNAME="$2"

KEYCLOAK_HOSTNAME="127.0.01:8443"

echo "🔐 Initializing Keycloak with required configurations..."

echo "    Waiting for Keycloak to be available..."
KEYCLOAK_AVAILABLE=false
MAX_ATTEMPTS=30
ATTEMPTS=0

while [ "$KEYCLOAK_AVAILABLE" = false ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    RESPONSE=$(curl -s -k --connect-timeout 5 https://${KEYCLOAK_HOSTNAME}/realms/master)
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

echo "    Authenticating with Keycloak Admin..."
echo "    Using admin password: ${ADMIN_PASSWORD}"
ADMIN_TOKEN=$(curl -k -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    "https://${KEYCLOAK_HOSTNAME}/realms/master/protocol/openid-connect/token" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo "❌ Error: Could not obtain a token for admin user. Please check credentials."
    exit 1
fi


echo "    Checking dashboard-frontend client..."
CLIENT_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "dashboard-frontend") | .clientId')

if [ -z "$CLIENT_EXISTS" ]; then
    echo "    Creating dashboard-frontend client..."
    RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "dashboard-frontend",
            "protocol": "openid-connect",
            "rootUrl": "http://'"${CLIENT_HOSTNAME}"'",
            "redirectUris": ["http://'"${CLIENT_HOSTNAME}"'/*"],
            "publicClient": true,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true
        }' \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error creating client: $RESPONSE"
    else
        echo "    Dashboard-frontend client created successfully."
    fi
else
    echo "    Dashboard-frontend client already exists, updating configuration..."
    CLIENT_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "dashboard-frontend") | .id')
    
    if [ -n "$CLIENT_ID" ]; then
        RESPONSE=$(curl -k -s -X PUT \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
                "clientId": "dashboard-frontend",
                "protocol": "openid-connect",
                "rootUrl": "http://'"${CLIENT_HOSTNAME}"'",
                "redirectUris": ["http://'"${CLIENT_HOSTNAME}"'/*"],
                "publicClient": true,
                "standardFlowEnabled": true,
                "directAccessGrantsEnabled": true
            }' \
            "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients/${CLIENT_ID}")
        
        if [[ "$RESPONSE" == *"error"* ]]; then
            echo "   ❌ Error updating client: $RESPONSE"
        else
            echo "    Dashboard-frontend client updated successfully."
        fi
    else
        echo "   ⚠️ Could not get dashboard-frontend client ID for update"
    fi
fi

sleep 2

CLIENT_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "dashboard-frontend") | .id')

if [ -n "$CLIENT_ID" ]; then
    CLIENT_SECRET=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients/${CLIENT_ID}/client-secret" | jq -r '.value')

    echo "    Dashboard-frontend client secret: ${CLIENT_SECRET}"
else
    echo "   ⚠️ Could not get dashboard-frontend client ID"
fi

echo "    Keycloak has been successfully initialized."