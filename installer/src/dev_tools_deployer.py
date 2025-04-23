import config
from installer.src.kube_client import get_secret, wait_for_deployment_available
from installer.tools.cert_manager import CertManager
from installer.tools.dashboard import Dashboard
from installer.tools.ingress import Ingress
from installer.tools.keycloak import Keycloak
from installer.tools.postgresql import Postgresql
from installer.tools.vault import Vault

class DevToolsDeployer:

    _instance = None
    is_installing = False

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(DevToolsDeployer, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        if hasattr(self, '_initialized') and self._initialized:
            return
        self.mandatory_tools_step = 0
        self._certManager = CertManager()
        self._ingress = Ingress()
        self._vault = Vault()
        self._postgresql = Postgresql()
        self._keycloak = Keycloak()
        self._dashboard = Dashboard()
        self.progress_steps = []
        self._initialized = True

    def install(self):
        self.is_installing = True
        try:
            secret = get_secret(secret_name='config')
            cert_type = secret['cert_type']
            self.progress_steps.clear()
            self.install_cert_manager()
            self.install_ingress()
            if cert_type == 'selfsigned': 
                self.install_vault()
            self.install_postgresql()
            self.install_keycloak()
            self.install_dashboard()
            self.progress_steps.append('Done')
        finally:
            self.is_installing = False

    def install_cert_manager(self):
        self.progress_steps.append('Installing cert-manager...')
        self._certManager.create_service_account()
        self._certManager.install()
        wait_for_deployment_available("cert-manager")
        wait_for_deployment_available("cert-manager-webhook")
        wait_for_deployment_available("cert-manager-cainjector")
        self._certManager.configure()

    def install_ingress(self):
        self.progress_steps.append('Installing ingress...')
        self._ingress.install()

    def install_vault(self):
        self.progress_steps.append('Installing vault...')
        self._vault.install()

    def install_postgresql(self):
        self.progress_steps.append('Installing postgresql...')
        self._postgresql.install()

    def install_keycloak(self):
        self.progress_steps.append('Installing keycloak...')
        self._keycloak.install()

    def install_dashboard(self):
        self.progress_steps.append('Installing dashboard...')
        self._dashboard.install()

devToolsDeployer = DevToolsDeployer()

__all__ = [
    "DevToolsDeployer",
    "devToolsDeployer"
]
