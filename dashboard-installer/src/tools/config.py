import tools.kube_init
from kubernetes import client
from kubernetes.client.rest import ApiException
from pyhelm.chartbuilder import ChartBuilder

core_api = client.CoreV1Api()

class Config:

    namespace = "dev-tools"

    def create_namespace(self):
        try:
            print("Checking for existing namespace...")
            core_api.read_namespace(name=self.namespace)
            print("Namespace already exists")
        except ApiException as e:
            print("Namespace not found, creating...")
            if e.status == 404:
                ns_body = client.V1Namespace(metadata=client.V1ObjectMeta(name=self.namespace))
                core_api.create_namespace(body=ns_body)
                print("Namespace created")
            else:
                raise

    def get_secret(self, secret_name):
        try:
            print("Checking for existing secret...")
            secret = core_api.read_namespaced_secret(name=secret_name, namespace=self.namespace)
            print("Secret found")
            return secret
        except ApiException as e:
            if e.status == 404:
                print("Secret not found")
                return None
            else:
                raise

    def create_secret(self, secret_name, data):
        secret_body = client.V1Secret(
            metadata=client.V1ObjectMeta(name=secret_name),
            data=data,
            type="Opaque",
        )
        try:
            core_api.create_namespaced_secret(namespace=self.namespace, body=secret_body)
            print("Secret created")
        except ApiException as e:
            if e.status == 409:
                core_api.replace_namespaced_secret(name=secret_name, namespace=self.namespace, body=secret_body)
                print("Secret replaced")
            else:
                raise
