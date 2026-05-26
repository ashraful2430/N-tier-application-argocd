#!/bin/bash
# Usage: ./scripts/run-tests.sh
set -euo pipefail
trap 'echo -e "[0;31mFailed at line $LINENO[0m" >&2' ERR
python -m venv backend/.venv
source backend/.venv/bin/activate
pip install --upgrade pip
pip install -e backend[dev]
ruff check backend/app
pytest backend
cd frontend
npm ci
npm run lint
npm run build
echo -e "[0;32mCompleted successfully[0m"
