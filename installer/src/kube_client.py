from kubernetes import config
import base64
from pathlib import Path
from kubernetes.stream import stream
from kubernetes import client
from kubernetes.client.rest import ApiException
import time
import subprocess

namespace = "dev-tools"

try:
    config.load_kube_config()
except Exception:
    config.load_incluster_config()

class KubeClient:

    def __init__(self):
        self.core_api = client.CoreV1Api()
        self.rbac_api = client.RbacAuthorizationV1Api()
        
    def set_namespace(self):

        namespaces = self.core_api.list_namespace()
        namespace_exists = False

        for ns in namespaces.items:
            if ns.metadata.name == self.kube_client.namespace:
                namespace_exists = True
                
        if namespace_exists:
            print(f"Namespace '{self.kube_client.namespace}' already exists")
        else:
            print(f"Namespace '{self.kube_client.namespace}' not found. Creating it...")
            ns_body = client.V1Namespace(metadata=client.V1ObjectMeta(name=self.kube_client.namespace))
            self.core_api.set_namespace(body=ns_body)
            print(f"Namespace '{self.kube_client.namespace}' created successfully")

    def get_secret(self, secret_name):
        try:
            secret = self.core_api.read_namespaced_secret(name=secret_name, namespace=self.kube_client.namespace)
            for key in secret.data:
                secret.data[key] = base64.b64decode(secret.data[key]).decode('utf-8')
            return secret.data
        except Exception as e:
            print(f"Error to get secret '{secret_name}': {e}")
            return None
        
    def set_secret(self, secret_name, data):
        secret_body = client.V1Secret(
            metadata=client.V1ObjectMeta(name=secret_name),
            data=data,
            type="Opaque",
        )
        try:
            self.core_api.set_namespaced_secret(namespace=self.kube_client.namespace, body=secret_body)
            print("Secret created")
        except ApiException as e:
            if e.status == 409:
                self.core_api.replace_namespaced_secret(name=secret_name, namespace=self.kube_client.namespace, body=secret_body)
                print("Secret replaced")
            else:
                raise


    def wait_for_deployment_available(self, deployment_name, timeout=300):
        apps_api = client.AppsV1Api()
        start = time.time()
        while True:
            try:
                dep = apps_api.read_namespaced_deployment(deployment_name, self.kube_client.namespace)
                for cond in dep.status.conditions or []:
                    if cond.type == "Available" and cond.status == "True":
                        print(f"{deployment_name} is available")
                        return True
            except ApiException as e:
                if e.status != 404:
                    print(f"Error: {e}")
            if time.time() - start > timeout:
                raise TimeoutError(f"Timeout waiting for deployment {deployment_name} to be available")
            time.sleep(3)

    def apply_kubectl(self, file_path):
        print(f"Applying {file_path}...")
        cmd = ["kubectl", "apply", "-f", file_path, "--namespace", self.kube_client.namespace]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout)
            raise RuntimeError(result.stderr)

    def exec_command(self, pod_name, command, env=None):
        if env:
            env_str = " ".join(f"{k}={v}" for k, v in env.items())
            full_command = f"{env_str} {command}"
        else:
            full_command = command
        exec_command = [
            '/bin/sh',
            '-c',
            full_command
        ]
        return stream(
            self.core_api.connect_get_namespaced_pod_exec,
            pod_name,
            self.kube_client.namespace,
            command=exec_command,
            stderr=True,
            stdin=False,
            stdout=True,
            tty=False,
        )

    def exec_script(self, script, params=None):
        script_path = Path(__file__).parent / script
        print(f"Running {script_path} ...")
        cmd = ["bash", str(script_path)]
        if params:
            cmd += [str(p) for p in params]
        try:
            subprocess.run(
                cmd,
                stdout=None,
                stderr=True,
                check=True
            )
        except subprocess.CalledProcessError as e:
            print(f"Error to execute {script_path}. Error: {e.stderr}")
            raise RuntimeError(f"Error to execute {script_path}: {e.stderr}")
        
    def exec_script_in_pod(self, pod_name, script, params=None, namespace="dev-tools"):
        project_root = Path(__file__).parent.parent
        script_path = project_root / script
        remote_path = f"/tmp/{Path(script).name}"
        print(f"Copying {script_path} to pod {pod_name}:{remote_path} ...")
        subprocess.run([
            "kubectl", "cp", str(script_path), f"{namespace}/{pod_name}:{remote_path}"
        ], check=True)
        cmd = ["kubectl", "exec", pod_name, "-n", namespace, "--", "bash", remote_path]
        if params:
            cmd += [str(p) for p in params]
        print(f"Running script in pod: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        print("[STDOUT]", result.stdout)
        if result.returncode != 0:
            print("[STDERR]", result.stderr)
            result.check_returncode()
        output_vars = {}
        for line in result.stdout.splitlines():
            if '=' in line and not line.strip().startswith('#'):
                k, v = line.split('=', 1)
                output_vars[k.strip()] = v.strip()
        return output_vars, result.stdout
        
    def wait_for_service_running(self, service, max_retries=30, retry_interval=10):
        core_api = client.CoreV1Api()
        retry_count = 0
        while retry_count < max_retries:
            retry_count += 1
            print(f"      Try {retry_count} of {max_retries}...")
            try:
                pods = core_api.list_namespaced_pod(
                    namespace=self.kube_client.namespace,
                    name=service,
                ).items
            except ApiException as e:
                pods = []
            if not pods:
                time.sleep(retry_interval)
                continue
            pod_status = pods[0].status.phase
            if pod_status == "Running":
                print(f"    {service} pod is Running.")
                break
            else:
                time.sleep(retry_interval)
        else:
            print(f"{service} was not Running after waiting {max_retries * retry_interval} seconds.")
            try:
                pod_name = pods[0].metadata.name if pods else None
                if pod_name:
                    desc = core_api.read_namespaced_pod(name=pod_name, namespace=self.kube_client.namespace)
                    print(desc)
            except Exception as e:
                print(f"Error describing pod: {e}")
                raise RuntimeError(f"{service} was not Running after waiting {max_retries * retry_interval} seconds.")
