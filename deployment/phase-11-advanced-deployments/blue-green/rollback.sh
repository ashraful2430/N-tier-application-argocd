#!/bin/bash
# Usage: ./rollback.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend-green
echo -e "[0;32mCompleted successfully[0m"
