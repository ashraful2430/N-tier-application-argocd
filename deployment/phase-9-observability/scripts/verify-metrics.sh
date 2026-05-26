#!/bin/bash
# Usage: ./scripts/verify-metrics.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
curl -fsS http://localhost:9090/-/healthy >/dev/null
echo -e "[0;32mCompleted successfully[0m"
