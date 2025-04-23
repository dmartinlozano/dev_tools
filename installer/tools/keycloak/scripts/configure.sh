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

# Check if devtools realm exists before authenticating
DEVTOOLS_REALM_EXISTS=$(curl -k -s http://${KEYCLOAK_HOSTNAME}/admin/realms | grep -o '"realm":"devtools"')

if [ -z "$DEVTOOLS_REALM_EXISTS" ]; then
    echo "    devtools realm does not exist, authenticating with admin in master realm..."
    ADMIN_TOKEN=$(curl -k -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        "http://${KEYCLOAK_HOSTNAME}/realms/master/protocol/openid-connect/token" | \
        grep -o '"access_token":"[^\"]*"' | awk -F'":"' '{print $2}' | awk -F'"' '{print $1}')
else
    echo "    devtools realm exists, authenticating with admin in devtools realm..."
    ADMIN_TOKEN=$(curl -k -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" \
        "http://${KEYCLOAK_HOSTNAME}/realms/devtools/protocol/openid-connect/token" | \
        grep -o '"access_token":"[^\"]*"' | awk -F'":"' '{print $2}' | awk -F'"' '{print $1}')
fi

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

# Create admin user in devtools realm if it does not exist
ADMIN_USER_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "http://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/users?username=admin" | grep -o '"username":"admin"')

if [ -z "$ADMIN_USER_EXISTS" ]; then
    echo "    Creating admin user in devtools realm..."
    CREATE_USER_RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{
            "username": "admin",
            "enabled": true,
            "emailVerified": true,
            "firstName": "Admin",
            "lastName": "User",
            "email": "admin@devtools.local"
        }' \
        "http://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/users")
    if [[ "$CREATE_USER_RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error creating admin user: $CREATE_USER_RESPONSE"
    else
        echo "    Admin user created successfully."
        # Get the ID of the created user
        ADMIN_USER_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
            "http://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/users?username=admin" | grep -o '"id":"[^"]*"' | head -n1 | cut -d'"' -f4)
        # Set the password
        if [ -n "$ADMIN_USER_ID" ]; then
            SET_PW_RESPONSE=$(curl -k -s -X PUT \
                -H "Authorization: Bearer ${ADMIN_TOKEN}" \
                -H "Content-Type: application/json" \
                -d '{"type":"password","value":"admin","temporary":false}' \
                "http://${KEYCLOAK_HOSTNAME}/admin/realms/devtools/users/${ADMIN_USER_ID}/reset-password")
            if [[ "$SET_PW_RESPONSE" == *"error"* ]]; then
                echo "   ❌ Error setting admin password: $SET_PW_RESPONSE"
            else
                echo "    Admin password set to 'admin'."
            fi
        fi
    fi
else
    echo "    Admin user already exists in devtools realm, skipping creation."
fi

# Delete admin user in master realm if it exists
MASTER_ADMIN_USER_EXISTS=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "http://${KEYCLOAK_HOSTNAME}/admin/realms/master/users?username=admin" | grep -o '"username":"admin"')
if [ -n "$MASTER_ADMIN_USER_EXISTS" ]; then 
    echo "    Deleting admin user in master realm..."
    MASTER_ADMIN_USER_ID=$(curl -k -s -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "http://${KEYCLOAK_HOSTNAME}/admin/realms/master/users?username=admin" | grep -o '"id":"[^"]*"' | head -n1 | cut -d'"' -f4)
    DELETE_USER_RESPONSE=$(curl -k -s -X DELETE \
        -H "Authorization: Bearer ${ADMIN_TOKEN}" \
        "http://${KEYCLOAK_HOSTNAME}/admin/realms/master/users/${MASTER_ADMIN_USER_ID}")
    if [[ "$DELETE_USER_RESPONSE" == *"error"* ]]; then
        echo "   ❌ Error deleting master admin user: $DELETE_USER_RESPONSE"
    else
        echo "    Master admin user deleted successfully."
    fi
else
    echo "    Master admin user does not exist, skipping deletion."
fi


echo "    Keycloak has been successfully initialized."