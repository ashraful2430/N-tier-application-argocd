#!/bin/bash
# Usage: sudo ./setup-ec2.sh [DOMAIN_NAME] [EMAIL]
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
if [[ $EUID -ne 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
DOMAIN_NAME="${1:-[DOMAIN_NAME]}"; ADMIN_EMAIL="${2:-[EMAIL]}"
[[ "$DOMAIN_NAME" != "[DOMAIN_NAME]" && "$ADMIN_EMAIL" != "[EMAIL]" ]] || { echo "Provide domain and email" >&2; exit 1; }
apt-get update -y && apt-get upgrade -y
apt-get install -y git curl ufw ca-certificates gnupg lsb-release unattended-upgrades
ufw allow OpenSSH; ufw allow 'Nginx Full'; ufw --force enable
timedatectl set-timezone UTC
mkdir -p /opt/devops-launchboard /var/www/devops-launchboard /etc/devops-launchboard
id -u launchboard >/dev/null 2>&1 || useradd --system --home /opt/devops-launchboard --shell /usr/sbin/nologin launchboard
chown -R launchboard:launchboard /opt/devops-launchboard /var/www/devops-launchboard
printf 'DOMAIN_NAME=%s
ADMIN_EMAIL=%s
' "$DOMAIN_NAME" "$ADMIN_EMAIL" >/etc/devops-launchboard/site.env
echo -e "${GREEN}Completed successfully${NC}"
