import config
import subprocess
import json
import yaml
import os
import tempfile

class HelmClient:

    def _run(self, cmd):
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(result.stderr)
        return result.stdout

    def install(self, name, location, values_file=None, extra_env_vars=None, values=None):
        cmd = ["helm", "upgrade", "--install", name, location, "--namespace", self.kube_client.namespace]
        if values_file:
            cmd += ["-f", values_file]
        if extra_env_vars:
            env_yaml = {
                "extraEnvVars": []
            }
            for key, value in extra_env_vars.items():
                env_yaml["extraEnvVars"].append({
                    "name": key,
                    "value": str(value)
                })            
            with tempfile.NamedTemporaryFile(mode='w+', suffix='.yaml', delete=False) as temp_file:
                yaml.dump(env_yaml, temp_file, default_flow_style=False)
                temp_file_path = temp_file.name
            cmd += ["-f", temp_file_path]

        if values:
            for k, v in values.items():
                cmd += ["--set", f"{k}={str(v).lower() if isinstance(v, bool) else v}"]

        result = self._run(cmd)

        if 'temp_file_path' in locals():
            try:
                os.remove(temp_file_path)
            except OSError as e:
                print(f"Error deleting temporary file: {e}")

        return result

    def uninstall(self, release):
        cmd = ["helm", "uninstall", release, "--namespace", self.kube_client.namespace]
        return self._run(cmd)

    def get_status(self, release):
        cmd = ["helm", "status", release, "--namespace", self.kube_client.namespace]
        return self._run(cmd)

    def list_releases(self):
        cmd = ["helm", "list", "--namespace", self.kube_client.namespace, "--output", "json"]
        output = self._run(cmd)
        return json.loads(output)

    def add_repo(self, repo, url):
        cmd = ["helm", "repo", "add", repo, url, "--force-update"]
        self._run(cmd)
        cmd = ["helm", "repo", "update"]
        return self._run(cmd)
