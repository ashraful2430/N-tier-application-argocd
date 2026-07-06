#!/bin/bash
set -eux

# Install Docker from the official repository
apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker ubuntu

# Discover this instance's public IP from the metadata service (IMDSv2)
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Write the Compose file - images are pre-built and pulled from Docker Hub
mkdir -p /opt/launchboard
cat > /opt/launchboard/docker-compose.yml << COMPOSE
services:
  launchboard-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: launchboard
      POSTGRES_USER: launchboard_user
      POSTGRES_PASSWORD: ${db_password}
    volumes:
      - launchboard-postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U launchboard_user -d launchboard"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    restart: unless-stopped

  launchboard-migrate:
    image: ${backend_image}
    command: ["alembic", "upgrade", "head"]
    environment:
      DATABASE_URL: postgresql+asyncpg://launchboard_user:${db_password}@launchboard-db:5432/launchboard
    depends_on:
      launchboard-db:
        condition: service_healthy
    restart: "no"

  launchboard-backend:
    image: ${backend_image}
    environment:
      DATABASE_URL: postgresql+asyncpg://launchboard_user:${db_password}@launchboard-db:5432/launchboard
      APP_NAME: DevOps LaunchBoard API
      APP_ENV: production
      CORS_ORIGINS: http://$PUBLIC_IP
      SEED_DEMO_DATA: "true"
    depends_on:
      launchboard-db:
        condition: service_healthy
      launchboard-migrate:
        condition: service_completed_successfully
    restart: unless-stopped

  launchboard-frontend:
    image: ${frontend_image}
    ports:
      - "80:8080"
    depends_on:
      launchboard-backend:
        condition: service_healthy
    restart: unless-stopped

volumes:
  launchboard-postgres-data:
COMPOSE

# Pull and start the stack
cd /opt/launchboard
docker compose pull
docker compose up -d
