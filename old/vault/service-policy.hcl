# Policy genérica para todos los servicios
path "secret/data/dev-tools/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Permitir lectura de secretos globales si algún chart lo requiere
path "secret/data/*" {
  capabilities = ["read", "list"]
}
