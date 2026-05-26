# DevOps LaunchBoard Deployment Guide

This deployment branch contains production-ready deployment assets for the DevOps LaunchBoard N-tier application: `launchboard-frontend` (Vite/React on Nginx), `launchboard-backend` (FastAPI on port `8000`), and `launchboard-db` (PostgreSQL 16). Backend health endpoints are `/health` and `/ready`; the frontend container exposes `/healthz`.

## Navigation

| Phase | Purpose |
| --- | --- |
| `phase-0-setup` | Workstation, AWS, naming, and cost guardrails |
| `phase-2-bare-metal` | EC2, systemd, Nginx, Certbot |
| `phase-3-docker` | Production Docker images and scanning |
| `phase-4-docker-compose` | Single-host full stack |
| `phase-5-docker-swarm` | Swarm services, secrets, rollback |
| `phase-6-kubernetes-local` | Local Kubernetes manifests |
| `phase-7-cicd` | GitHub Actions and Jenkins |
| `phase-8-eks` | Terraform-managed EKS |
| `phase-9-observability` | Prometheus, Grafana, logs, Jaeger |
| `phase-10-security` | Vault, RBAC, policies, SAST |
| `phase-11-advanced-deployments` | Blue-green, canary, feature flags |
| `phase-12-disaster-recovery` | Backups, restore, chaos, runbooks |

## Replace Before Use

Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` with lab values. Deploy in order: database, migrations, backend, frontend.

## Cost Warning

Local Docker and local Kubernetes are usually free. AWS phases can charge for EC2, EKS, NAT gateways, load balancers, EBS, snapshots, S3, CloudWatch, and Secrets Manager. Use budgets and destroy lab resources after each class.

## Fast Start

```bash
cd deployment/phase-4-docker-compose
cp .env.example .env
./scripts/init-db.sh
docker compose up -d --build
./scripts/health-check.sh
```
