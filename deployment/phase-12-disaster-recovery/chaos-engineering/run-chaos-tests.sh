#!/bin/bash
# Usage: ./chaos-engineering/run-chaos-tests.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
kubectl apply -f chaos-engineering/kill-pod-experiment.yaml
kubectl apply -f chaos-engineering/litmus-chaos.yaml
echo -e "[0;32mCompleted successfully[0m"
