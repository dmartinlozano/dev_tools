#!/bin/bash
set -e

MINIKUBE_IP=""
CURRENT_CONTEXT=$(kubectl config current-context --kubeconfig "$KUBECONFIG_TEMP")
echo "The current kubeconfig context is: $CURRENT_CONTEXT"
echo -n "Do you want to continue installing in this context? [y/N]: "
read -r CONTEXT_CONFIRM
if [[ ! "$CONTEXT_CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Installation aborted by user."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker/Colima is not running or not responding. Please start Colima (colima start) and try again."
  exit 1
fi

if lsof -i :8001 | grep 'kubectl' >/dev/null 2>&1; then
  echo "Stopping existing kubectl proxy on port 8001..."
  lsof -i :8001 | grep 'kubectl' | awk '{print $2}' | xargs kill || true
  sleep 1
fi

if lsof -i :8080 | grep -E 'python|node' >/dev/null 2>&1; then
  echo "Closing user processes using port 8080 (python/node)..."
  lsof -i :8080 | grep -E 'python|node' | awk '{print $2}' | xargs kill || true
  sleep 1
fi

echo "Starting kubectl proxy in background on port 8001..."
kubectl proxy --address=0.0.0.0 --disable-filter=true &
KUBECTL_PROXY_PID=$!
sleep 2

# Dashboard

cd installer/tools/dashboard
if [[ "$CURRENT_CONTEXT" == "minikube" ]]; then
  eval $(minikube docker-env)
  #docker build --no-cache -t dashboard:local .
  docker build -t dashboard:local .
  eval $(minikube docker-env -u)
else
  docker build --no-cache -t dashboard:local .
fi
cd ../../

# Installer

#docker build --no-cache -t dev-tools-installer:local .
docker build -t dev-tools-installer:local .

mkdir -p ".tmp"
cp "$HOME/.kube/config" ".tmp/config"

KUBECONFIG_TEMP=".tmp/config"

while IFS= read -r line; do
  if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ "$line" =~ :[[:space:]]*(\/[^[:space:]\"\']+) ]]; then
    original_path="${BASH_REMATCH[1]}"
    filename=$(basename "$original_path")
    echo "Found path: $original_path, copying to .tmp/$filename"
    if [ -f "$original_path" ]; then
      cp "$original_path" ".tmp/$filename"
      if grep -q "$original_path" "$KUBECONFIG_TEMP"; then
        sed -i.bak "s|$original_path|/root/.kube/$filename|g" "$KUBECONFIG_TEMP"
        echo "Path replaced: $original_path -> /root/.kube/$filename"
      else
        echo "[WARNING] Path $original_path not found in kubeconfig, skipping sed replacement"
      fi
      if [ ! -f ".tmp/$filename" ]; then
        echo "[ERROR] File .tmp/$filename was not created!"
      fi
    else
      echo "[WARNING] File $original_path not found, skipping"
    fi
  fi
done < "$KUBECONFIG_TEMP"
rm -f "${KUBECONFIG_TEMP}.bak"

if [[ "$CURRENT_CONTEXT" == "minikube" ]]; then
  MINIKUBE_IP=$(minikube ip)
fi

if grep -q 'server: https://127.0.0.1:' "$KUBECONFIG_TEMP"; then
  sed -i.bak -E "s|server: https://127.0.0.1:([0-9]+)|server: https://${MINIKUBE_IP}:\1|g" "$KUBECONFIG_TEMP"
  rm -f "${KUBECONFIG_TEMP}.bak"
fi
if grep -q 'server: https://localhost:' "$KUBECONFIG_TEMP"; then
  sed -i.bak -E "s|server: https://localhost:([0-9]+)|server: https://${MINIKUBE_IP}:\1|g" "$KUBECONFIG_TEMP"
  rm -f "${KUBECONFIG_TEMP}.bak"
fi
if grep -q 'minikube.sigs.k8s.io' "$KUBECONFIG_TEMP"; then
  echo "Minikube context detected. Replacing API server with http://host.docker.internal:8001 for kubectl proxy access."
  sed -i.bak -E 's|server: https://[0-9.]+:[0-9]+|server: http://host.docker.internal:8001|g' "$KUBECONFIG_TEMP"
  rm -f "${KUBECONFIG_TEMP}.bak"
fi

docker run --rm -it \
  -v "$(pwd)/.tmp:/root/.kube:ro" \
  -e KUBECONFIG="/root/.kube/config" \
  -e MINIKUBE_IP="$MINIKUBE_IP" \
  -p 8080:8080 \
  dev-tools-installer:local

if [ -n "$KUBECTL_PROXY_PID" ]; then
  echo "Stopping kubectl proxy (PID $KUBECTL_PROXY_PID)..."
  kill $KUBECTL_PROXY_PID || true
fi

rm -rf ".tmp"