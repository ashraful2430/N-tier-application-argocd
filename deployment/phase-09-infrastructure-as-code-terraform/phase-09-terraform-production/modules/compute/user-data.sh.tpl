#!/bin/bash
set -eux

# Install Docker from the official repository
apt-get update
apt-get install -y ca-certificates curl unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Install AWS CLI v2 (needed for ECR login and SSM parameter read)
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# Read the database password from SSM Parameter Store (IAM role grants access)
DB_PASSWORD=$(aws ssm get-parameter \
  --name "${db_password_ssm_name}" \
  --with-decryption \
  --region "${aws_region}" \
  --query Parameter.Value \
  --output text)

DATABASE_URL="postgresql+asyncpg://${db_username}:$DB_PASSWORD@${db_endpoint}/${db_name}"

# Log in to ECR and pull the app images
aws ecr get-login-password --region "${aws_region}" \
  | docker login --username AWS --password-stdin "${ecr_registry}"
docker pull "${backend_image}"
docker pull "${frontend_image}"

# Shared network so the frontend can reach the backend by container name
docker network create launchboard || true

# Run database migrations (alembic is idempotent; already-applied migrations are skipped)
docker run --rm --network launchboard \
  -e DATABASE_URL="$DATABASE_URL" \
  "${backend_image}" alembic upgrade head

# Backend API
docker run -d --name launchboard-backend --network launchboard \
  --restart unless-stopped \
  -e DATABASE_URL="$DATABASE_URL" \
  -e APP_NAME="DevOps LaunchBoard API" \
  -e APP_ENV=production \
  -e CORS_ORIGINS="http://${alb_dns_name}" \
  -e SEED_DEMO_DATA=true \
  "${backend_image}"

# Frontend (Nginx serving the built app and proxying /api to the backend)
docker run -d --name launchboard-frontend --network launchboard \
  --restart unless-stopped \
  -p 80:8080 \
  "${frontend_image}"
