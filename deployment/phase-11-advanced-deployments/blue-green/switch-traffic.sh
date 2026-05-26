#!/bin/bash
# Usage: ./switch-traffic.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
TRACK="${1:-green}"
kubectl -n devops-launchboard patch service launchboard-backend -p "{\"spec\":{\"selector\":{\"app\":\"launchboard-backend\",\"track\":\"$TRACK\"}}}"
echo -e "[0;32mCompleted successfully[0m"
