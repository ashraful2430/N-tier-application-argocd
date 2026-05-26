#!/bin/bash
# Usage: ./scripts/setup-rbac.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl apply -f k8s-security/
echo -e "[0;32mCompleted successfully[0m"
