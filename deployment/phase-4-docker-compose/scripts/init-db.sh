#!/bin/bash
# Usage: ./scripts/init-db.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
[[ -f .env ]] || cp .env.example .env
mkdir -p volumes/postgres
chmod 700 volumes/postgres || true
echo -e "${GREEN}Completed successfully${NC}"
