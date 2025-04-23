import config
from helm_client import HelmClient
from pathlib import Path

class Ingress:

    def __init__(self):
        self.helm_client = HelmClient()

    def install(self):
        print("Installing ingress...")
        self.helm_client.add_repo(
            repo="ingress-nginx",
            url="https://kubernetes.github.io/ingress-nginx"
        )
        self.helm_client.install(
            name="ingress-nginx",
            location="ingress-nginx/ingress-nginx",
            values_file=Path(__file__).parent / "values.yaml",
        )
        print("ingress installed")

__all__ = ["Ingress"]