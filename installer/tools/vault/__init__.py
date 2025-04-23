import base64
from installer.src.helm_client import HelmClient
from installer.src.kube_client import KubeClient
from kubernetes import client
from pathlib import Path
import json
import ast

class Vault:

    def __init__(self):
        self.pod_name = "vault-0"
        self.core_v1 = client.CoreV1Api()
        self.helm_client = HelmClient()
        self.kube_client = KubeClient()

    def install(self):
        self.helm_client.list_releases()
        releases = self.helm_client.list_releases()
        release_exists = any(release["name"] == "vault" for release in releases)
        if release_exists:
            print("Vault is already installed. Skipping installation.")
            status = KubeClient.exec_command(
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
                self.kube_client.wait_for_pod_container_ready(
                    pod_name=self.pod_name,
                    namespace="dev-tools",
                    container_name="vault",
                )
                secret = self.kube_client.get_secret('vault-unseal-keys')
                if not secret or 'unseal_keys_b64' not in secret:
                    raise RuntimeError("Vault unseal keys not found in secret 'vault-unseal-keys'.")
                unseal_keys_raw = secret.get('unseal_keys_b64')
                try:
                    unseal_keys = json.loads(unseal_keys_raw)
                except Exception:
                    unseal_keys = [k for k in unseal_keys_raw.split() if k]
                t = status.get("t", 3)
                for key in unseal_keys[:t]:
                    self.kube_client.exec_command(
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
            self.kube_client.wait_for_service_running("vault")
            config_data = self.kube_client.get_secret(secret_name="config")
            base_dns = config_data["base_dns"]
            configure_script = str(Path(__file__).parent / "configure.sh")
            self.kube_client.exec_script(configure_script, [base_dns])
            print("vault installed.")

    def set_credentials(self, vault_path, username, password):
        secret =  self.kube_client.get_secret("vault-token")
        self.kube_client.exec_command(
            pod_name="vault-0",
            command=f"vault kv put secret/dev-tools/{vault_path} username=\"{username}\" password=\"{password}\"",
            env={"VAULT_TOKEN": secret["key"]},
        )

    def get_credentials(self, vault_path, field):
        try:
            secret =  self.kube_client.get_secret("vault-token")
            value = self.kube_client.exec_command(
                pod_name="vault-0",
                command=f"vault kv get -field={field} secret/dev-tools/{vault_path}",
                env={"VAULT_TOKEN": secret["key"]},
            )
            if "No value found at" in value:
                return None
            else:
                return value.strip()
        except Exception as e:
            return None


__all__ = ["Vault"]