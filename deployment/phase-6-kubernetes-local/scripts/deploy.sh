#!/bin/bash
# Usage: ./scripts/deploy.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v kubectl >/dev/null
kubectl apply -k k8s
kubectl -n devops-launchboard wait --for=condition=available deployment/launchboard-backend --timeout=180s
kubectl -n devops-launchboard wait --for=condition=available deployment/launchboard-frontend --timeout=180s
echo -e "[0;32mCompleted successfully[0m"
