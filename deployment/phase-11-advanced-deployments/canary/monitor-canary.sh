#!/bin/bash
# Usage: ./monitor-canary.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl argo rollouts get rollout launchboard-backend -n devops-launchboard --watch
echo -e "[0;32mCompleted successfully[0m"
