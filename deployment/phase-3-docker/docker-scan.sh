#!/bin/bash
# Usage: ./docker-scan.sh image:tag
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
IMAGE_REF="${1:-}"; [[ -n "$IMAGE_REF" ]] || { echo "Usage: $0 image:tag" >&2; exit 1; }
command -v trivy >/dev/null || { echo "trivy is required" >&2; exit 1; }
trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed "$IMAGE_REF"
echo -e "${GREEN}Completed successfully${NC}"
