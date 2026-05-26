#!/bin/bash
# Usage: ./scripts/migrate.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
docker compose run --rm launchboard-migrate
echo -e "${GREEN}Completed successfully${NC}"
