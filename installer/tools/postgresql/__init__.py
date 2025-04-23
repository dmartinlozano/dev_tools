from installer.src.helm_client import HelmClient
from installer.src.kube_client import exec_command, wait_for_service_running
from installer.tools.vault.vault_utils import set_credentials
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
        set_credentials(vault_path="postgresql/admin", username="postgres", password=postgres_password)    
        exec_command(
            pod_name="postgresql-0",
            command=f"kubectl exec -it postgresql-0 -- psql -U postgres -c '\\du'",
            env={"PGPASSWORD": postgres_password},
        )
        print("postgresql installed")

    def create_database(database_name):

        username = get_credentials(vault_path=f"postgresql/{database_name}", field="username")
        password = get_credentials(vault_path=f"postgresql/{database_name}", field="password")

        if not username:
            username = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(4))
        
        if not password:
            password = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20))

        set_credentials(
            vault_path=f"postgresql/{database_name}",
            username=username,
            password=password,
        )

        postgres_password = get_credentials(vault_path="postgresql/admin", field="password")

        exists_db = exec_command(
            pod_name="postgresql-0",
            command=f"psql -U postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='{database_name}'\";",
            env={"PGPASSWORD": postgres_password},
        )
        
        if '1' not in exists_db:
            exec_command(
                pod_name="postgresql-0",
                command=f"psql -U postgres -c \"CREATE DATABASE \\\"{database_name}\\\" ENCODING 'UTF8';\"",
                env={"PGPASSWORD": postgres_password},
            )

        #Check if user exists
        exists_user = exec_command(
            pod_name="postgresql-0",
            command=f"psql -U postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='{username}'\";",
            env={"PGPASSWORD": postgres_password},
        )

        if '1' in exists_user:
            # If user exists, update password
            exec_command(
                pod_name="postgresql-0",
                command=f"psql -U postgres -c \"ALTER USER \\\"{username}\\\" WITH ENCRYPTED PASSWORD '{password}';\"",
                env={"PGPASSWORD": postgres_password},
            )
        else:
            # if user does not exist, create it
            exec_command(
                pod_name="postgresql-0",
                command=f"psql -U postgres -c \"CREATE USER \\\"{username}\\\" WITH ENCRYPTED PASSWORD '{password}';\"",
                env={"PGPASSWORD": postgres_password},
            )
        
        exec_command(
            pod_name="postgresql-0",
            command=f"psql -U postgres -c \"GRANT ALL PRIVILEGES ON DATABASE \\\"{database_name}\\\" TO \\\"{username}\\\";\"",
            env={"PGPASSWORD": postgres_password},
        )
        
        exec_command(
            pod_name="postgresql-0",
            command=f"psql -U postgres -d \"{database_name}\" -c \"GRANT USAGE ON SCHEMA public TO \\\"{username}\\\";\"",
            env={"PGPASSWORD": postgres_password},
        )
        
        exec_command(
            pod_name="postgresql-0",
            command=f"psql -U postgres -d \"{database_name}\" -c \"GRANT CREATE ON SCHEMA public TO \\\"{username}\\\";\"",
            env={"PGPASSWORD": postgres_password},
        )

        print(f"    Database {database_name} created successfully.") 
        return username, password

__all__ = ["Postgresql"]