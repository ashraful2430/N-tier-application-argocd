#!/bin/bash
set -eux

# Install Docker from the official repository
apt-get update
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu

# Discover this instance's public IP from the metadata service (IMDSv2)
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# Clone the app and configure the Compose environment
git clone https://github.com/ashraful2430/N-tier-application.git /opt/launchboard
cd /opt/launchboard/deployment/phase-04-docker-compose
cp .env.example .env
sed -i "s|CHANGE_ME_STRONG_PASSWORD|${db_password}|g" .env
sed -i "s|http://YOUR_EC2_PUBLIC_IP|http://$PUBLIC_IP|g" .env

# Build and start the full stack
docker compose up -d --build
