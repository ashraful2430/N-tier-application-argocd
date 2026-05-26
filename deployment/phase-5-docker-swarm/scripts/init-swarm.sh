#!/bin/bash
# Usage: ./scripts/init-swarm.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
command -v docker >/dev/null
docker info --format "{{.Swarm.LocalNodeState}}" | grep -q active || docker swarm init
echo -e "[0;32mCompleted successfully[0m"
