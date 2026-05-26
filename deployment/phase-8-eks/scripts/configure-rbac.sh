#!/bin/bash
# Usage: ./scripts/configure-rbac.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl create namespace devops-launchboard --dry-run=client -o yaml | kubectl apply -f -
kubectl -n devops-launchboard create serviceaccount deployer --dry-run=client -o yaml | kubectl apply -f -
echo -e "[0;32mCompleted successfully[0m"
