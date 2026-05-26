#!/bin/bash
# Usage: ./scripts/scan-images.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
IMAGE="${1:-}"; [[ -n "$IMAGE" ]] || { echo "Usage: $0 image:tag" >&2; exit 1; }
trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed "$IMAGE"
echo -e "[0;32mCompleted successfully[0m"
