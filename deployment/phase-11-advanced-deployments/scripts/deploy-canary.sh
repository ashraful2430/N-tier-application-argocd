#!/bin/bash
# Usage: ./scripts/deploy-canary.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl apply -f canary/canary-service.yaml
kubectl apply -f canary/argo-rollout.yaml
echo -e "[0;32mCompleted successfully[0m"
