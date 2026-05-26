#!/bin/bash
# Usage: ./scripts/deploy-monitoring.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f prometheus/alert-rules.yaml
kubectl apply -f jaeger/
echo -e "[0;32mCompleted successfully[0m"
