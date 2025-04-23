path "secret/data/dev-tools/keycloak/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/keycloak" {
  capabilities = ["read", "list"]
}

path "secret/data/dev-tools/keycloak/admin" {
  capabilities = ["create", "read", "update", "delete", "list"]
}