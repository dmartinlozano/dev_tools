from installer.src.helm_client import HelmClient
from installer.src.utils import exec_command, exec_script, get_secret, wait_for_service_running
from kubernetes import client
from pathlib import Path
import json
import ast

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
            status = exec_command(
                pod_name=self.pod_name,
                command="vault status -format=json",
            )
            if isinstance(status, dict):
                status_dict = status
            else:
                if status.strip().startswith("{") and "'" in status:
                    status_dict = ast.literal_eval(status)
                else:
                    status_json = status.strip().split('\n')[-1]
                    status_dict = json.loads(status_json)
            status = status_dict
            if status.get("sealed") is True:
                print("Vault is sealed. Unsealing...")
                secret = get_secret('vault-unseal-keys')
                if not secret or 'unseal_keys_b64' not in secret:
                    raise RuntimeError("Vault unseal keys not found in secret 'vault-unseal-keys'.")
                unseal_keys = json.loads(secret['unseal_keys_b64'])
                t = status.get("t", 3)
                for key in unseal_keys[:t]:
                    exec_command(
                        pod_name=self.pod_name,
                        command=f"vault operator unseal {key}",
                    )
                print("Vault unsealed")
                
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