#!/bin/bash
set -e

# Print warning and exit if user cancels
NAMESPACE="dev-tools"

read -p "⚠️  Are you sure you want to delete ALL resources in the namespace '$NAMESPACE'? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "❌ Operation cancelled. Nothing has been deleted."
  exit 1
fi

# Uninstall all helm releases
helm list -n "$NAMESPACE" -q | while read -r release; do
  helm uninstall "$release" -n "$NAMESPACE"
done

# Delete all standard resources
kubectl delete all --all -n "$NAMESPACE"

# Delete additional resources
kubectl delete secret --all -n "$NAMESPACE"
kubectl delete configmap --all -n "$NAMESPACE"
kubectl delete pvc --all -n "$NAMESPACE"
kubectl delete cronjob --all -n "$NAMESPACE"
kubectl delete ingress --all -n "$NAMESPACE"
kubectl delete job --all -n "$NAMESPACE"

# Delete common custom resources (CRDs)
kubectl delete secretproviderclass --all -n "$NAMESPACE"
kubectl delete serviceaccount --all -n "$NAMESPACE"

# Delete the namespace (uncomment if desired)
kubectl delete namespace "$NAMESPACE"

echo "✅ All resources in namespace $NAMESPACE have been deleted."
