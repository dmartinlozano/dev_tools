1. ClusterIssuer: ingress-issuer
  - Es el emisor de certificados TLS utilizado tanto en desarrollo como en producción.
  - En desarrollo, se implementa como un ClusterIssuer de Vault (Vault PKI).
  - En producción, se implementa como un ClusterIssuer de Let's Encrypt (ACME).
  - Los manifiestos Certificate siempre referencian a ingress-issuer, y se aplica el ClusterIssuer correspondiente según el entorno.

2. Certificate: services-tls
  - Es un certificado TLS para los servicios bajo el dominio *.dev-tools.svc.cluster.local.
  - Es emitido por el ClusterIssuer ingress-issuer y almacenado en el secreto services-tls.
  - Tiene una validez de 1 año y se renueva 30 días antes de expirar.
  - Permite comunicaciones seguras (HTTPS) entre los servicios internos del namespace dev-tools.

3. Certificate: vault-ts
  - Es un certificado TLS específico para el pod de Vault.
  - Es emitido por el ClusterIssuer ingress-issuer y almacenado en el secreto vault-ts.
  - Se monta en el pod de Vault para habilitar la comunicación segura (TLS) del propio servicio Vault.

En resumen:
- ingress-issuer: emisor único referenciado por los certificados, implementado con Vault en dev y Let's Encrypt en prod.
- services-tls: certificado TLS para servicios internos, emitido por ingress-issuer.
- vault-ts: certificado TLS específico para Vault, emitido por ingress-issuer y montado en el pod de Vault.