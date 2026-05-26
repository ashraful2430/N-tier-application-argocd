#!/bin/bash
# Usage: ./scripts/test-local.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v kubectl >/dev/null
kubectl -n devops-launchboard port-forward svc/launchboard-frontend 8080:80 >/tmp/launchboard-port-forward.log 2>&1 & PF=$!
sleep 3
curl -fsS http://127.0.0.1:8080/healthz >/dev/null
kill $PF
echo -e "[0;32mCompleted successfully[0m"
