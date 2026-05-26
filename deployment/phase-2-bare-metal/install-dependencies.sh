#!/bin/bash
# Usage: sudo ./install-dependencies.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
if [[ $EUID -ne 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
apt-get update -y
apt-get install -y python3.12 python3.12-venv python3-pip nodejs npm nginx postgresql postgresql-contrib certbot python3-certbot-nginx
systemctl enable --now postgresql nginx
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='launchboard'" | grep -q 1 || sudo -u postgres psql -c "CREATE USER launchboard WITH PASSWORD '[DB_PASSWORD]';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='launchboard'" | grep -q 1 || sudo -u postgres createdb -O launchboard launchboard
cat >/etc/devops-launchboard/backend.env <<'ENV'
APP_NAME=DevOps LaunchBoard API
APP_ENV=production
DATABASE_URL=postgresql+asyncpg://launchboard:[DB_PASSWORD]@127.0.0.1:5432/launchboard
CORS_ORIGINS=https://[DOMAIN_NAME]
SEED_DEMO_DATA=false
ENV
chmod 640 /etc/devops-launchboard/backend.env
chown root:launchboard /etc/devops-launchboard/backend.env
echo -e "${GREEN}Completed successfully${NC}"
