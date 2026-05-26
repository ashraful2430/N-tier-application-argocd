#!/bin/bash
# Usage: ./disaster-recovery/test-failover.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s
echo -e "[0;32mCompleted successfully[0m"
