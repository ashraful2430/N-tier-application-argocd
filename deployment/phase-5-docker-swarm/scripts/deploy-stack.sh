#!/bin/bash
# Usage: ./scripts/deploy-stack.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v docker >/dev/null
docker secret inspect db_password >/dev/null 2>&1 || printf "%s" "${DB_PASSWORD:-[DB_PASSWORD]}" | docker secret create db_password -
docker stack deploy -c stack.yml devops-launchboard
echo -e "[0;32mCompleted successfully[0m"
