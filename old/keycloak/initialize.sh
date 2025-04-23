#!/bin/bash
set -e

# This script is running only in a job inside the dev-tools namespace
apt-get update && apt-get install -y curl jq

ADMIN_PASSWORD="$1"
KEYCLOAK_HOSTNAME="keycloak.dev-tools.svc.cluster.local:8443"
DASHBOARD_HOSTNAME="dashboard-frontend.dev-tools.svc.cluster.local"

echo "🔐 Initializing Keycloak with required configurations..."

echo "   ▪ Waiting for Keycloak to be available..."
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
    echo "   ▪ Keycloak is not available yet (attempt $ATTEMPTS/$MAX_ATTEMPTS). Waiting 10s..."
    sleep 10
done

if [ "$KEYCLOAK_AVAILABLE" = false ]; then
    echo "❌ Error: Keycloak is not available after $MAX_ATTEMPTS attempts. Please check your Keycloak deployment."
    exit 1
fi

echo "   ▪ Authenticating with Keycloak Admin..."
echo "   ▪ Using admin password: ${ADMIN_PASSWORD}"
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

echo "   ▪ Checking dev-tools realm..."
REALM_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms" | jq -r '.[] | select(.realm == "devtools") | .realm')

if [ -z "$REALM_EXISTS" ]; then
    echo "   ▪ Creating dev-tools realm..."
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
        "https://${KEYCLOAK_HOSTNAME}/admin/realms")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error creating realm: $RESPONSE"
    else
        echo "   ▪ Devtools realm created successfully."
    fi
else
    echo "   ▪ Devtools realm already exists, skipping creation."
fi

echo "   ▪ Checking dashboard-frontend client..."
CLIENT_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "dashboard-frontend") | .clientId')

if [ -z "$CLIENT_EXISTS" ]; then
    echo "   ▪ Creating dashboard-frontend client..."
    RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "clientId": "dashboard-frontend",
            "protocol": "openid-connect",
            "rootUrl": "http://'"${DASHBOARD_HOSTNAME}"'",
            "redirectUris": ["http://'"${DASHBOARD_HOSTNAME}"'/*"],
            "publicClient": true,
            "standardFlowEnabled": true,
            "directAccessGrantsEnabled": true
        }' \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error creating client: $RESPONSE"
    else
        echo "   ▪ Dashboard-frontend client created successfully."
    fi
else
    echo "   ▪ Dashboard-frontend client already exists, updating configuration..."
    CLIENT_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients" | jq -r '.[] | select(.clientId == "dashboard-frontend") | .id')
    
    if [ -n "$CLIENT_ID" ]; then
        RESPONSE=$(curl -k -s -X PUT \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
                "clientId": "dashboard-frontend",
                "protocol": "openid-connect",
                "rootUrl": "http://'"${DASHBOARD_HOSTNAME}"'",
                "redirectUris": ["http://'"${DASHBOARD_HOSTNAME}"'/*"],
                "publicClient": true,
                "standardFlowEnabled": true,
                "directAccessGrantsEnabled": true
            }' \
            "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/clients/${CLIENT_ID}")
        
        if [[ "$RESPONSE" == *"error"* ]]; then
            echo "   ❌ Error updating client: $RESPONSE"
        else
            echo "   ▪ Dashboard-frontend client updated successfully."
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

    echo "   ▪ Dashboard-frontend client secret: ${CLIENT_SECRET}"
else
    echo "   ⚠️ Could not get dashboard-frontend client ID"
fi

echo "   ▪ Checking global roles..."
for ROLE in "admin" "edit" "view"; do
    ROLE_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/roles" | jq -r '.[] | select(.name == "'"${ROLE}"'") | .name')
    
    if [ -z "$ROLE_EXISTS" ]; then
        echo "   ▪ Creating ${ROLE} role..."
        RESPONSE=$(curl -k -s -X POST \
            -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" \
            -d '{
                "name": "'"${ROLE}"'",
                "description": "'"${ROLE}"' role"
            }' \
            "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/roles")
        
        if [[ "$RESPONSE" == *"error"* ]]; then
            echo "   ❌ Error creating role: $RESPONSE"
        else
            echo "   ▪ Role ${ROLE} created successfully."
        fi
    else
        echo "   ▪ Role ${ROLE} already exists, skipping creation."
    fi
done

echo "   ▪ Setting up required actions for new users..."
RESPONSE=$(curl -k -s -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "registrationEmailAsUsername": false,
        "editUsernameAllowed": true,
        "resetPasswordAllowed": true,
        "verifyEmail": false
    }' \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools")

if [[ "$RESPONSE" == *"error"* ]]; then
    echo "   ❌ Error configuring realm settings: $RESPONSE"
else
    echo "   ▪ Realm settings configured successfully."
fi

echo "   ▪ Setting default required actions for new users in devtools realm..."
RESPONSE=$(curl -k -s -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "alias": "UPDATE_PASSWORD",
        "name": "Update Password",
        "providerId": "UPDATE_PASSWORD",
        "enabled": true,
        "defaultAction": true,
        "priority": 10,
        "config": {}
    }' \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/authentication/required-actions/UPDATE_PASSWORD")

if [[ "$RESPONSE" == *"error"* ]]; then
    echo "   ❌ Error configuring UPDATE_PASSWORD required action for devtools realm: $RESPONSE"
else
    echo "   ▪ UPDATE_PASSWORD required action configured successfully for devtools realm. New users will be required to change password on first login."
fi

echo "   ▪ Setting default required actions for users in master realm..."
RESPONSE=$(curl -k -s -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "alias": "UPDATE_PASSWORD",
        "name": "Update Password",
        "providerId": "UPDATE_PASSWORD",
        "enabled": true,
        "defaultAction": true,
        "priority": 10,
        "config": {}
    }' \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/master/authentication/required-actions/UPDATE_PASSWORD")

if [[ "$RESPONSE" == *"error"* ]]; then
    echo "   ❌ Error configuring UPDATE_PASSWORD required action for master realm: $RESPONSE"
else
    echo "   ▪ UPDATE_PASSWORD required action configured successfully for master realm. Users like 'admin' will be required to change password on first login."
fi

echo "   ▪ Setting required action specifically for admin user (if needed)..."
ADMIN_USER_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "https://${KEYCLOAK_HOSTNAME}/admin/realms/master/users?username=admin" | jq -r '.[0].id')

if [ -n "$ADMIN_USER_ID" ]; then
    RESPONSE=$(curl -k -s -X PUT \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "requiredActions": ["UPDATE_PASSWORD"]
        }' \
        "https://${KEYCLOAK_HOSTNAME}/admin/realms/master/users/${ADMIN_USER_ID}")
    
    if [[ "$RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error setting UPDATE_PASSWORD action for admin user: $RESPONSE"
    else
        echo "   ▪ UPDATE_PASSWORD action set specifically for admin user successfully."
    fi
else
    echo "   ⚠️ Could not find admin user ID to set required actions."
fi

echo "   ▪ Keycloak has been successfully initialized."