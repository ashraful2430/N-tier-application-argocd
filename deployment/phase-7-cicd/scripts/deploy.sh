#!/bin/bash
# Usage: ./scripts/deploy.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
TAG="${1:-[IMAGE_TAG]}"
kubectl -n devops-launchboard set image deployment/launchboard-backend backend=[AWS_ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/launchboard-backend:$TAG
kubectl -n devops-launchboard set image deployment/launchboard-frontend frontend=[AWS_ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/launchboard-frontend:$TAG
kubectl -n devops-launchboard rollout status deployment/launchboard-backend --timeout=180s
echo -e "[0;32mCompleted successfully[0m"
