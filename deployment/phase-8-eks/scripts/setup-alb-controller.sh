#!/bin/bash
# Usage: ./scripts/setup-alb-controller.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=devops-launchboard --set serviceAccount.create=true
echo -e "[0;32mCompleted successfully[0m"
