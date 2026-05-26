#!/bin/bash
# Usage: ./backup/scripts/backup-now.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
velero backup create launchboard-manual-$(date +%Y%m%d%H%M%S) --include-namespaces devops-launchboard
echo -e "[0;32mCompleted successfully[0m"
