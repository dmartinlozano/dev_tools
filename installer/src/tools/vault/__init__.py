from tools.utils import exec_script, get_secret, wait_for_service_running
from kubernetes import client
from tools.helm_client import HelmClient
from pathlib import Path

class Vault:

    def __init__(self):
        self.pod_name = "vault-0"
        self.core_v1 = client.CoreV1Api()
        self.helm_client = HelmClient()
    
   
    def install(self):
        self.helm_client.list_releases()
        releases = self.helm_client.list_releases()
        release_exists = any(release["name"] == "vault" for release in releases)
        if release_exists:
            print("Vault is already installed. Skipping installation.")
            return
        else:
            print("Installing vault...")
            self.helm_client.add_repo(
                repo="hashicorp",
                url="https://helm.releases.hashicorp.com",
            )
            self.helm_client.install(
                name="vault",
                location="hashicorp/vault",
                values_file=Path(__file__).parent / "values/values.yaml"
            )
            wait_for_service_running("vault")
            config_data = get_secret(secret_name="config")
            base_dns = config_data["base_dns"]
            configure_script = str(Path(__file__).parent / "configure.sh")
            exec_script(configure_script, [base_dns])
            print("vault installed.")

__all__ = ["Vault"]