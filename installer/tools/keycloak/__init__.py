from installer.src import config
from installer.src.helm_client import HelmClient
from installer.src.kube_client import exec_script_in_pod, get_secret, wait_for_service_running
from installer.tools.postgresql import Postgresql
from installer.tools.vault.vault_utils import set_credentials, get_credentials
from kubernetes import client
from pathlib import Path
import base64
import tempfile
import os
import subprocess
import secrets
import string

core_api = client.CoreV1Api()

class Keycloak:

    keystore_password = None

    def __init__(self):
        self.helm_client = HelmClient()
        self.postgresql = Postgresql()

    def install(self):

        print("Installing keycloak...")

        self.keystore_password = get_credentials(vault_path="keycloak/keystore", field="password")
        if not self.keystore_password:
            self.keystore_password = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))
        set_credentials(
            vault_path="keycloak/keystore",
            username="keystore",
            password=self.keystore_password,
        )

        self.create_keystore()

        db_user, db_password = self.postgresql.create_database("keycloak")

        config_data = get_secret(secret_name="config")
        base_dns = config_data["base_dns"]
        admin_password = get_credentials(vault_path="keycloak/admin", field="password")
        if not admin_password:
            admin_password = config_data["admin_password"]
        kecycloak_hostname = f"keycloak.{base_dns}"

        self.helm_client.add_repo(
            repo="bitnami",
            url="https://charts.bitnami.com/bitnami"
        )
        self.helm_client.install(
            name="keycloak",
            location="bitnami/keycloak",
            values_file=Path(__file__).parent / "values.yaml",
            values={
                "externalDatabase.user": db_user,
                "externalDatabase.password": db_password,
                "auth.adminPassword": admin_password,
                "ingress.hostname": kecycloak_hostname,
                "tls.keystorePassword": self.keystore_password
            },
            extra_env_vars={
                "KC_HOSTNAME": kecycloak_hostname,
                "KC_HTTPS_TRUST_STORE_PASSWORD": self.keystore_password,
            }
        )
        wait_for_service_running("keycloak")
        set_credentials(vault_path="keycloak/admin", username="admin", password=admin_password)  


        # wait for keycloak api to be available
        print("Waiting configuring keycloak...")
        script_path = Path(__file__).parent / "scripts" / "configure.sh"
        _, output = exec_script_in_pod(
            pod_name="keycloak-0",
            script=str(script_path),
            params=[
                admin_password
            ]
        )
        print("keycloak configuration:", output)
        print("keycloak installed")


    def create_keystore(self):

        # extract secrets
        secret = core_api.read_namespaced_secret("services-tls", self.kube_client.namespace)

        with tempfile.TemporaryDirectory() as tmpdir:
            crt_path = os.path.join(tmpdir, "tls.crt")
            key_path = os.path.join(tmpdir, "tls.key")
            ca_path = os.path.join(tmpdir, "ca.crt")
            p12_path = os.path.join(tmpdir, "keycloak.p12")
            keystore_path = os.path.join(tmpdir, "keycloak.keystore.jks")
            truststore_path = os.path.join(tmpdir, "keycloak.truststore.jks")

            with open(crt_path, "wb") as f:
                f.write(base64.b64decode(secret.data["tls.crt"]))
            with open(key_path, "wb") as f:
                f.write(base64.b64decode(secret.data["tls.key"]))
            with open(ca_path, "wb") as f:
                f.write(base64.b64decode(secret.data["ca.crt"]))

            # PKCS12
            subprocess.check_call([
                "openssl", "pkcs12", "-export",
                "-in", crt_path,
                "-inkey", key_path,
                "-certfile", ca_path,
                "-out", p12_path,
                "-name", "keycloak",
                "-password", f"pass:{self.keystore_password}"
            ], stderr=subprocess.STDOUT, stdout=subprocess.PIPE)

            # JKS
            subprocess.check_call([
                "keytool", "-importkeystore",
                "-deststorepass", self.keystore_password,
                "-destkeypass", self.keystore_password,
                "-destkeystore", keystore_path,
                "-srckeystore", p12_path,
                "-srcstoretype", "PKCS12",
                "-srcstorepass", self.keystore_password,
                "-alias", "keycloak"
            ], stderr=subprocess.STDOUT, stdout=subprocess.PIPE)

            subprocess.check_call([
                "keytool", "-importcert",
                "-file", ca_path,
                "-alias", "rootca",
                "-keystore", truststore_path,
                "-storepass", self.keystore_password,
                "-noprompt"
            ], stderr=subprocess.STDOUT, stdout=subprocess.PIPE)

            # Add keystore to secret
            with open(keystore_path, "rb") as f:
                keystore_data = base64.b64encode(f.read()).decode("utf-8")
            with open(truststore_path, "rb") as f:
                truststore_data = base64.b64encode(f.read()).decode("utf-8")

        secret = core_api.read_namespaced_secret("services-tls", self.kube_client.namespace)
        secret.data["keycloak.keystore.jks"] = keystore_data
        secret.data["keycloak.truststore.jks"] = truststore_data
        core_api.replace_namespaced_secret("services-tls", self.kube_client.namespace, secret)
