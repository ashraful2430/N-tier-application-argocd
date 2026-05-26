#!/bin/bash
# Usage: ./scripts/deploy-app.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl apply -f k8s/
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s
echo -e "[0;32mCompleted successfully[0m"
