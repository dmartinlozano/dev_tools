from pathlib import Path
from kubernetes import client
from installer.src.helm_client import HelmClient
from installer.src.utils import exec_script_in_pod, get_secret, wait_for_service_running

class Dashboard:

    def __init__(self):
        self.core_v1 = client.CoreV1Api()
        self.helm_client = HelmClient()

    def install(self):
        print("Installing dashboard...")
        secret = get_secret(secret_name="config")
        base_dns = secret['base_dns']
        cert_type = secret['cert_type']
        self.helm_client.install(
            name="dashboard",
            location=str(Path(__file__).parent),
            values_file=Path(__file__).parent / "values.yaml",
            values={
                "DASHBOARD_HOSTNAME": f"dashboard.{base_dns}",
                "BASE_DNS": base_dns,
                "CERT_TYPE": cert_type,
            }
        )
        wait_for_service_running("dashboard")

        script_path = Path(__file__).parent.parent / "keycloak" / "scripts" / "client.sh"
        
        exec_script_in_pod(
            pod_name="keycloak-0",
            script=str(script_path),
            params=["dashboard"]
        )