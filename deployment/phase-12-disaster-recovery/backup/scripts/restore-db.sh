#!/bin/bash
# Usage: ./backup/scripts/restore-db.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
BACKUP="${1:-}"; [[ -n "$BACKUP" ]] || { echo "Usage: $0 backup-name" >&2; exit 1; }
velero restore create --from-backup "$BACKUP"
echo -e "[0;32mCompleted successfully[0m"
