#!/bin/bash
# Usage: sudo ./ssl-setup.sh [DOMAIN_NAME] [EMAIL]
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
if [[ $EUID -ne 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
DOMAIN_NAME="${1:-[DOMAIN_NAME]}"; ADMIN_EMAIL="${2:-[EMAIL]}"
[[ "$DOMAIN_NAME" != "[DOMAIN_NAME]" && "$ADMIN_EMAIL" != "[EMAIL]" ]] || { echo "Provide domain and email" >&2; exit 1; }
nginx -t
certbot --nginx -d "$DOMAIN_NAME" --email "$ADMIN_EMAIL" --agree-tos --non-interactive --redirect
systemctl reload nginx
echo -e "${GREEN}Completed successfully${NC}"
