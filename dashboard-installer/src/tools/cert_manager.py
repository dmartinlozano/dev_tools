import tools.kube_init
from kubernetes import client
from kubernetes.client.rest import ApiException
from pyhelm.chartbuilder import ChartBuilder

core_api = client.CoreV1Api()
rbac_api = client.RbacAuthorizationV1Api()

class CertManager:
    namespace = "dev-tools"
    sa_name = "dev-tools-sa"
    crb_name = "dev-tools-crb"

    def create_service_account(self):
        try:
            print("Checking for existing ServiceAccount...")
            core_api.read_namespaced_service_account(name=self.sa_name, namespace=self.namespace)
            print("ServiceAccount already exists")
        except ApiException as e:
            print(f"ApiException: {e}")
            if e.status == 404:
                print("ServiceAccount not found, creating...")
                sa_body = client.V1ServiceAccount(metadata=client.V1ObjectMeta(name=self.sa_name))
                core_api.create_namespaced_service_account(namespace=self.namespace, body=sa_body)
                print("ServiceAccount created")
                crb_body = client.V1ClusterRoleBinding(
                    metadata=client.V1ObjectMeta(name=self.crb_name),
                    role_ref=client.V1RoleRef(
                        api_group="rbac.authorization.k8s.io",
                        kind="ClusterRole",
                        name="system:service-account-token-creator"
                    ),
                    subjects=[
                        client.V1Subject(
                            kind="ServiceAccount",
                            name=self.sa_name,
                            namespace=self.namespace
                        )
                    ]
                )
                rbac_api.create_cluster_role_binding(body=crb_body)
                print("ClusterRoleBinding created")
            else:
                print(f"ApiException (not 404): {e}", exc_info=True)
                raise
        except Exception as ex:
            print(f"Unexpected exception: {ex}", exc_info=True)
            raise

    def install_cert_manager(self):
        try:
            # Check if cert-manager is already installed
            core_api.read_namespaced_pod(name="cert-manager", namespace=self.namespace)
            print("cert-manager already installed")
        except ApiException as e:
            if e.status == 404:
                print("cert-manager not found, installing...")
                chart = ChartBuilder(
                    name="cert-manager",
                    repo_url="https://charts.jetstack.io",
                    version="v1.13.0",
                    namespace=self.namespace,
                    values={"installCRDs": True}
                )
                chart.install(namespace=self.namespace)
                print("cert-manager installed")
            else:
                raise
        except Exception as ex:
            print(f"Unexpected exception: {ex}", exc_info=True)
            raise