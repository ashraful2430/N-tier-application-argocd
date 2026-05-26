#!/bin/bash
# Usage: ./build-and-push.sh [AWS_ACCOUNT_ID] [REGION] [IMAGE_TAG]
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
AWS_ACCOUNT_ID="${1:-[AWS_ACCOUNT_ID]}"; REGION="${2:-[REGION]}"; IMAGE_TAG="${3:-[IMAGE_TAG]}"
for cmd in docker aws; do command -v "$cmd" >/dev/null || { echo "$cmd is required" >&2; exit 1; }; done
REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
for repo in launchboard-backend launchboard-frontend; do aws ecr describe-repositories --repository-names "$repo" --region "$REGION" >/dev/null 2>&1 || aws ecr create-repository --repository-name "$repo" --region "$REGION" >/dev/null; done
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build -f deployment/phase-3-docker/Dockerfile.backend -t "$REGISTRY/launchboard-backend:$IMAGE_TAG" .
docker build -f deployment/phase-3-docker/Dockerfile.frontend --build-arg VITE_API_URL=/api -t "$REGISTRY/launchboard-frontend:$IMAGE_TAG" .
docker push "$REGISTRY/launchboard-backend:$IMAGE_TAG"; docker push "$REGISTRY/launchboard-frontend:$IMAGE_TAG"
echo -e "${GREEN}Completed successfully${NC}"
