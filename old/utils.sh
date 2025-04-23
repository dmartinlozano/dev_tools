run() {
  EXEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOG_FILE="$EXEC_DIR/.exec.log"
  "$@" > "$LOG_FILE" 2>&1
  if [ $? -ne 0 ]; then
    echo "❌  Error executing: $*"
    cat $LOG_FILE
    exit 1
  fi
}

get-dns() {
  if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    CLUSTER_IP=$(minikube ip)
    echo "${CLUSTER_IP}.nip.io"
  else
    INGRESS_IP=$(kubectl get svc -n dev-tools ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -z "$INGRESS_IP" ]; then
      INGRESS_IP=$(kubectl get svc -n dev-tools ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    fi
    if [ -z "$INGRESS_IP" ]; then
      echo "local"
    else
      echo "${INGRESS_IP}.nip.io"
    fi
  fi
}

wait_for_service_ready() {
  SERVICE="$1"
  MAX_RETRIES=60
  RETRY_INTERVAL=10
  RETRY_COUNT=0
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "     ▪ Try $RETRY_COUNT of $MAX_RETRIES..."
    PODS=$(kubectl get pods -l app.kubernetes.io/name=$SERVICE -n dev-tools --no-headers 2>/dev/null | grep -v '^$')
    if [ -z "$PODS" ]; then
      sleep $RETRY_INTERVAL
      continue
    fi
    READY_STATUS=$(kubectl get pods -l app.kubernetes.io/name=$SERVICE -n dev-tools -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
    POD_STATUS=$(kubectl get pods -l app.kubernetes.io/name=$SERVICE -n dev-tools -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ "$READY_STATUS" = "true" ] && [ "$POD_STATUS" = "Running" ]; then
      echo "   ▪ $SERVICE pod is ready."
      break
    else
      sleep $RETRY_INTERVAL
    fi
  done
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌  $SERVICE was not ready after waiting $(($MAX_RETRIES * $RETRY_INTERVAL)) seconds."
    echo "📋  Last pod status:"
    kubectl describe pod -l app.kubernetes.io/name=$SERVICE -n dev-tools
    exit 1
  fi
}

wait_for_service_running() {
  SERVICE="$1"
  MAX_RETRIES=30
  RETRY_INTERVAL=10
  RETRY_COUNT=0
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "     ▪ Try $RETRY_COUNT of $MAX_RETRIES..."
    PODS=$(kubectl get pods -l app.kubernetes.io/name=$SERVICE -n dev-tools --no-headers 2>/dev/null | grep -v '^$')
    if [ -z "$PODS" ]; then
      echo "   ▪ $SERVICE pod not found. Waiting..."
      sleep $RETRY_INTERVAL
      continue
    fi
    POD_STATUS=$(kubectl get pods -l app.kubernetes.io/name=$SERVICE -n dev-tools -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" = "Running" ]; then
      echo "   ▪ $SERVICE pod is Running."
      break
    else
      sleep $RETRY_INTERVAL
    fi
  done
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌  $SERVICE was not Running after waiting $(($MAX_RETRIES * $RETRY_INTERVAL)) seconds."
    echo "📋  Last pod status:"
    kubectl describe pod -l app.kubernetes.io/name=$SERVICE -n dev-tools
    exit 1
  fi
}

wait_for_job() {
  local job_name="$1"
  local max_retries=30
  local retry_interval=10
  local retry_count=0
  echo "   ▪ Waiting for job $job_name to complete..."
  while [ $retry_count -lt $max_retries ]; do
    status=$(kubectl get job "$job_name" -n dev-tools -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
    failed=$(kubectl get job "$job_name" -n dev-tools -o jsonpath='{.status.failed}' 2>/dev/null)
    if [ "$status" = "True" ]; then
      echo "   ▪ $job_name completed successfully."
      return 0
    elif [ -n "$failed" ] && [ "$failed" -gt 0 ]; then
      echo "❌ Job $job_name failed. Showing logs:"
      pod_name=$(kubectl get pods -n dev-tools --selector=job-name=$job_name -o jsonpath='{.items[0].metadata.name}')
      kubectl logs $pod_name -n dev-tools
      return 1
    else
      echo "   ▪ Waiting for job $job_name... ($((retry_count+1))/$max_retries)"
      sleep $retry_interval
      retry_count=$((retry_count+1))
    fi
  done
  echo "❌ Job $job_name did not complete in time. Showing logs:"
  pod_name=$(kubectl get pods -n dev-tools --selector=job-name=$job_name -o jsonpath='{.items[0].metadata.name}')
  kubectl logs $pod_name -n dev-tools
  return 1
}

run_script_as_job() {
  local script_path="$1"
  shift
  local cmd="[\"/bin/bash\", \"/script.sh\"$(printf ', \"%s\"' "$@")]"
  local job_name="job-$(date +%s)"

  kubectl create configmap "${job_name}-script" --from-file=script.sh="${script_path}" -n dev-tools

  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: dev-tools
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: runner
        image: bitnami/minideb:latest
        command: $cmd
        volumeMounts:
        - name: script
          mountPath: /script.sh
          subPath: script.sh
      volumes:
      - name: script
        configMap:
          name: ${job_name}-script
EOF

  wait_for_job ${job_name}
}

save_secret_literal() {
  local key="$1"
  local value="$2"
  local tmpfile=$(mktemp)

  if kubectl get secret config -n dev-tools &>/dev/null; then
    kubectl get secret config -n dev-tools -o yaml > "$tmpfile"
  else
    cat > "$tmpfile" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: config
  namespace: dev-tools
type: Opaque
data: {}
EOF
  fi

  local encoded_value
  encoded_value=$(printf "%s" "$value" | base64 | tr -d '\n')
  if grep -q "^  $key:" "$tmpfile"; then
    yq e ".data.$key = \"$encoded_value\"" -i "$tmpfile"
  else
    yq e ".data.$key = \"$encoded_value\"" -i "$tmpfile"
  fi

  kubectl apply -f "$tmpfile"
  rm "$tmpfile"
}

get_secret_literal() {
  kubectl get secret config -n dev-tools -o jsonpath="{.data.$1}" 2>/dev/null | base64 --decode
  echo
}