from installer.src.helm_client import HelmClient
from installer.src.utils import exec_command, wait_for_service_running
from installer.tools.vault.vault_utils import create_credentials
from pathlib import Path
import secrets
import string

class Postgresql:

    def __init__(self):
        self.helm_client = HelmClient()

    def install(self):
        
        print("Installing postgresql...")
        postgres_password = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))

        self.helm_client.add_repo(
            repo="bitnami",
            url="https://charts.bitnami.com/bitnami"
        )
        self.helm_client.install(
            name="postgresql",
            location="bitnami/postgresql",
            values={"auth.postgresPassword": postgres_password},
            values_file=Path(__file__).parent / "values.yaml",
        )
        wait_for_service_running("postgresql")
        create_credentials(vault_path="postgresql/admin", username="postgres", password=postgres_password)    
        exec_command(
            pod_name="postgresql-0",
            command=f"kubectl exec -it postgresql-0 -- psql -U postgres -c '\\du'",
            env={"PGPASSWORD": postgres_password},
        )
        print("postgresql installed")

__all__ = ["Postgresql"]