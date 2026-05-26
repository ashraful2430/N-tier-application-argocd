#!/bin/bash
# Usage: ./scripts/deploy-eks.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
aws eks update-kubeconfig --region [REGION] --name devops-launchboard
echo -e "[0;32mCompleted successfully[0m"
