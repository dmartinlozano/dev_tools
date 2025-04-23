# Policy genérica para todos los servicios
path "secret/data/dev-tools/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Permitir lectura de secretos globales si algún chart lo requiere
path "secret/data/*" {
  capabilities = ["read", "list"]
}

# Permisos para cert-manager pueda firmar certificados
path "pki/sign/dev-tools" {
  capabilities = ["create", "read", "update"]
}

# Permisos para listar y leer certificados
path "pki/cert/*" {
  capabilities = ["read", "list"]
}

# Permisos para validar roles de PKI
path "pki/roles/dev-tools" {
  capabilities = ["read"]
}
