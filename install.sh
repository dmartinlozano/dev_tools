#!/bin/bash
set -e

cd installer

echo "[INFO] Building Docker image..."
docker build -t dev-tools-installer:local .

mkdir -p ".tmp"
cp "$HOME/.kube/config" ".tmp/config"

KUBECONFIG_TEMP=".tmp/config"

echo "[INFO] Processing kubeconfig file..."
while IFS= read -r line; do
  if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ "$line" =~ :[[:space:]]*(\/[^[:space:]\"\']+) ]]; then
    original_path="${BASH_REMATCH[1]}"
    filename=$(basename "$original_path")
    echo "[INFO] Found path: $original_path, copying to .tmp/$filename"
    if [ -f "$original_path" ]; then
      cp "$original_path" ".tmp/$filename"
      sed -i.bak "s|${original_path}|/root/.kube/${filename}|g" "$KUBECONFIG_TEMP"
      echo "[INFO] Path replaced: ${original_path} -> /.kube/${filename}"
    else
      echo "[WARNING] File $original_path not found, skipping"
    fi
  fi
done < "$KUBECONFIG_TEMP"

rm -f "${KUBECONFIG_TEMP}.bak"
echo "[INFO] Kubeconfig processed successfully"
echo "[INFO] Running container..."

docker run --rm -it \
  -v "$(pwd)/.tmp:/root/.kube:ro" \
  -e KUBECONFIG="/root/.kube/config" \
  -p 8000:8000 \
  dev-tools-installer:local

rm -rf ".tmp"