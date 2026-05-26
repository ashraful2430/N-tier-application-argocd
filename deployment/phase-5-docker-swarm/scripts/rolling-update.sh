#!/bin/bash
# Usage: ./scripts/rolling-update.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v docker >/dev/null
S="${1:-}"; I="${2:-}"; [[ -n "$S" && -n "$I" ]] || { echo "Usage: $0 service image:tag" >&2; exit 1; }
docker service update --image "$I" --with-registry-auth "$S"
echo -e "[0;32mCompleted successfully[0m"
