path "transit/decrypt/vault-unseal-key" {
  capabilities = ["update"]
}
path "transit/encrypt/vault-unseal-key" {
  capabilities = ["update"]
}
path "transit/keys/vault-unseal-key" {
  capabilities = ["read"]
}
path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}