from installer.src import config
from installer.src.helm_client import HelmClient
from installer.src.kube_client import apply_kubectl, get_secret
from pathlib import Path
from kubernetes import client
import tempfile

class CertManager:

    def __init__(self):
        self.sa_name = "dev-tools-sa"
        self.crb_name = "dev-tools-crb"
        self.core_api = client.CoreV1Api()
        self.rbac_api = client.RbacAuthorizationV1Api()
        self.api_client = client.ApiClient()
        self.helm_client = HelmClient()

    def create_service_account(self):
            
        print("Checking for existing ServiceAccount...")

        service_accounts = self.core_api.list_namespaced_service_account(namespace=self.kube_client.namespace)
        
        sa_exists = False
        for sa in service_accounts.items:
            if sa.metadata.name == self.sa_name:
                sa_exists = True
        
        if sa_exists:
            print("ServiceAccount already exists")
        else:
            print(f"ServiceAccount {self.sa_name} not found, creating...")
            sa_body = client.V1ServiceAccount(metadata=client.V1ObjectMeta(name=self.sa_name))
            self.core_api.set_namespaced_service_account(namespace=self.kube_client.namespace, body=sa_body)
            print("ServiceAccount created")
            crb_body = client.V1ClusterRoleBinding(
                metadata=client.V1ObjectMeta(name=self.crb_name),
                role_ref=client.V1RoleRef(
                    api_group="rbac.authorization.k8s.io",
                    kind="ClusterRole",
                    name="system:service-account-token-creator"
                ),
                subjects=[
                    client.RbacV1Subject(
                        kind="ServiceAccount",
                        name=self.sa_name,
                        namespace=self.kube_client.namespace
                    )
                ]
            )
            self.rbac_api.create_cluster_role_binding(body=crb_body)
            print("ClusterRoleBinding created")
                

    def install(self):
        print("installing cert-manager...")
        self.helm_client.add_repo(
            repo="jetstack",
            url="https://charts.jetstack.io"
        )
        self.helm_client.install(
            name="cert-manager",
            location="jetstack/cert-manager",
            values={"installCRDs": True}
        )
        print("cert-manager installed")

    def configure(self):

        print("Configuring tls...")

        base_path = Path(__file__).resolve().parent
        yaml_path = base_path / "values/roles.yaml"
        apply_kubectl(str(yaml_path))
        
        secret = get_secret(secret_name='config')
        cert_type = secret["cert_type"]
        if cert_type == "selfsigned":
            yaml_path = base_path / 'values/vault.yaml'
        else:
            yaml_path = base_path / 'values/letsencrypt.yaml'
        apply_kubectl(str(yaml_path))

        config_data = get_secret(secret_name="config")
        base_dns = config_data["base_dns"]
        yaml_path = base_path / "values/ingress.yaml"
        with open(yaml_path) as f:
            manifest = f.read()
        manifest = manifest.replace("${BASE_DNS}", base_dns)
        with tempfile.TemporaryDirectory() as tmpdir:
            with open(f"{tmpdir}/ingress.yaml", "w") as f:
                f.write(manifest)
            apply_kubectl(f"{tmpdir}/ingress.yaml")

        print("tls configured")
        
installer = CertManager()

__all__ = ["CertManager", "installer"]