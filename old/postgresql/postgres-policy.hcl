# (Ya no es necesario, la policy genérica service-policy.hcl cubre todos los servicios)
path "secret/data/dev-tools/postgresql/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/*" {
  capabilities = ["read", "list"]
}
path "secret/*" {
  capabilities = ["read", "list"]
}