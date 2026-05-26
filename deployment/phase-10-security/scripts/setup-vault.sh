#!/bin/bash
# Usage: ./scripts/setup-vault.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
vault status || true
vault secrets enable -path=secret kv-v2 || true
echo -e "[0;32mCompleted successfully[0m"
