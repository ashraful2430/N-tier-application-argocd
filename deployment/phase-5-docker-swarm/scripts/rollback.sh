#!/bin/bash
# Usage: ./scripts/rollback.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v docker >/dev/null
S="${1:-devops-launchboard_launchboard-backend}"; docker service rollback "$S"
echo -e "[0;32mCompleted successfully[0m"
