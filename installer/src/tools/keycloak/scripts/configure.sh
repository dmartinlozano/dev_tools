#!/bin/bash

ADMIN_PASSWORD="$1"
KEYCLOAK_HOSTNAME="127.0.0.1:8080"

echo "🔐 Initializing Keycloak with required configurations..."

echo "    Waiting for Keycloak to be available..."
KEYCLOAK_AVAILABLE=false
MAX_ATTEMPTS=30
ATTEMPTS=0

while [ "$KEYCLOAK_AVAILABLE" = false ] && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    RESPONSE=$(curl -s -k --connect-timeout 5 http://${KEYCLOAK_HOSTNAME}/realms/master)
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
ADMIN_TOKEN=$(curl -k -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    "http://${KEYCLOAK_HOSTNAME}/realms/master/protocol/openid-connect/token" | \
    grep -o '"access_token":"[^"]*"' | awk -F'":"' '{print $2}' | awk -F'"' '{print $1}')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
    echo "❌ Error: Could not obtain a token for admin user. Please check credentials."
    exit 1
fi

echo "    Checking dev-tools realm..."
REALM_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "http://${KEYCLOAK_HOSTNAME}/admin/realms" | \
    grep -o '"realm":"devtools"')

if [ -z "$REALM_EXISTS" ]; then
    echo "    Creating dev-tools realm..."
    RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "realm": "devtools",
            "enabled": true,
            "displayName": "DevTools",
            "registrationAllowed": false,
            "loginWithEmailAllowed": true,
            "resetPasswordAllowed": true
        }' \
        "http://${KEYCLOAK_HOSTNAME}/admin/realms")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error creating realm: $RESPONSE"
    else
        echo "    Devtools realm created successfully."
    fi
else
    echo "    Devtools realm already exists, skipping creation."
fi

echo "    Checking global roles..."
for ROLE in "admin" "edit" "view"; do
    ROLE_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "http://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/roles" | \
        grep -o '"name":"'"${ROLE}"'"')
    
    if [ -z "$ROLE_EXISTS" ]; then
        echo "    Creating ${ROLE} role..."
        RESPONSE=$(curl -k -s -X POST \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "'"${ROLE}"'",
                "description": "'"${ROLE}"' role"
            }' \
            "http://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/roles")
        
        if [[ "$RESPONSE" == *"error"* ]]; then
            echo "   ❌ Error creating role: $RESPONSE"
        else
            echo "    Role ${ROLE} created successfully."
        fi
    else
        echo "    Role ${ROLE} already exists, skipping creation."
    fi
done

echo "    Keycloak has been successfully initialized."