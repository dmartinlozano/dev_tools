from kubernetes import config

namespace = "dev-tools"

try:
    config.load_kube_config()
except Exception:
    config.load_incluster_config()