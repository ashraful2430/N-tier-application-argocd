#!/bin/bash
# Usage: ./scripts/health-check.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
for u in http://localhost:8000/health http://localhost:8000/ready http://localhost:8080/healthz; do curl -fsS "$u" >/dev/null; done
echo -e "${GREEN}Completed successfully${NC}"
