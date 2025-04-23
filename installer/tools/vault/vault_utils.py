from utils import exec_command
import config
from kubernetes import client
import base64

def create_credentials(vault_path, username, password):
    core_api = client.CoreV1Api()
    secret = core_api.read_namespaced_secret("vault-token", config.namespace)
    vault_token = base64.b64decode(secret.data["key"]).decode("utf-8")
    exec_command(
        pod_name="vault-0",
        command=f"vault kv put secret/dev-tools/{vault_path} username=\"{username}\" password=\"{password}\"",
        env={"VAULT_TOKEN": vault_token},
    )

def get_credentials(vault_path, field):
    try:
        core_api = client.CoreV1Api()
        secret = core_api.read_namespaced_secret("vault-token", config.namespace)
        vault_token = base64.b64decode(secret.data["key"]).decode("utf-8")
        value = exec_command(
            pod_name="vault-0",
            command=f"vault kv get -field={field} secret/dev-tools/{vault_path}",
            env={"VAULT_TOKEN": vault_token},
        )
        if "No value found at" in value:
            return None
        else:
            return value.strip()
    except Exception as e:
        return None

