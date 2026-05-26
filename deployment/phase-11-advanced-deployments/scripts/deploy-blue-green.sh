#!/bin/bash
# Usage: ./scripts/deploy-blue-green.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl apply -f blue-green/blue-deployment.yaml
kubectl apply -f blue-green/green-deployment.yaml
echo -e "[0;32mCompleted successfully[0m"
