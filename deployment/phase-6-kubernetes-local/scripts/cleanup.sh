#!/bin/bash
# Usage: ./scripts/cleanup.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v kubectl >/dev/null
kubectl delete -k k8s --ignore-not-found=true
echo -e "[0;32mCompleted successfully[0m"
