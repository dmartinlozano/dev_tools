import tools.kube_init
from kubernetes import client
from tools.cert_manager import CertManager
from tools.config import Config
import queue

class Installer:
    _progress_queues = {}

    def __init__(self, progress_id):
        self.progress_id = progress_id
        if progress_id not in Installer._progress_queues:
            Installer._progress_queues[progress_id] = queue.Queue()
        self.progress_queue = Installer._progress_queues[progress_id]

    def get_progress_queue(self):
        return self.progress_queue

    def install(self):
        self.install_cert_manager()
        self.progress_queue.put('done')

    def install_cert_manager(self):
        Config().create_namespace()
        self.progress_queue.put('Installing cert-manager...')
        CertManager().create_service_account()
        self.progress_queue.put('cert-manager installed.')
