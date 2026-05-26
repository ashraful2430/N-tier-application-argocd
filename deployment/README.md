# DevOps LaunchBoard Deployment Guide

This `deployment/` directory is the production deployment branch guide for the DevOps LaunchBoard N-tier application. It is written for students who are learning how a real project moves from a local machine to Docker, Kubernetes, AWS EKS, monitoring, security, release strategies, and disaster recovery.

The application has three main services:

| Service | What It Does | Technology | Port | Health Check |
| --- | --- | --- | ---: | --- |
| `launchboard-frontend` | Browser UI for students and operators | Vite/React served by Nginx | `8080` in containers | `/healthz` |
| `launchboard-backend` | REST API and business logic | FastAPI/Uvicorn | `8000` | `/health`, `/ready` |
| `launchboard-db` | Persistent application data | PostgreSQL 16 | `5432` | `pg_isready` |

## How To Use This Directory

Start with `phase-0-setup`, then move phase by phase. Each phase has its own README, scripts, manifests, and configuration files. The goal is that a student can open one phase, read the README, replace the bracket variables, run the commands, and understand what happened.

## Phase Map

| Phase | Topic | Main Learning Outcome |
| --- | --- | --- |
| `phase-0-setup` | Workstation and cloud prep | Install tools, set naming rules, understand cost risk |
| `phase-2-bare-metal` | EC2 without containers | Run app directly with Linux services and Nginx |
| `phase-3-docker` | Container images | Build secure, small, non-root images |
| `phase-4-docker-compose` | Single-host stack | Run DB, migrations, API, and UI together |
| `phase-5-docker-swarm` | Swarm orchestration | Deploy replicated services with secrets and rollback |
| `phase-6-kubernetes-local` | Local Kubernetes | Learn Deployments, Services, Ingress, PVC, HPA |
| `phase-7-cicd` | Automation | Test, scan, build, push, deploy, and rollback |
| `phase-8-eks` | AWS Kubernetes | Provision EKS with Terraform and deploy app |
| `phase-9-observability` | Monitoring and logs | Add metrics, alerts, dashboards, logs, and traces |
| `phase-10-security` | Hardening | Apply RBAC, NetworkPolicy, Vault, SAST, image scanning |
| `phase-11-advanced-deployments` | Safer releases | Practice blue-green, canary, and feature flags |
| `phase-12-disaster-recovery` | Recovery | Back up, restore, test failover, and run incident playbooks |

## Values Students Must Replace

| Placeholder | Example | Meaning |
| --- | --- | --- |
| `[PROJECT_NAME]` | `devops-launchboard` | Project name used in tags and resources |
| `[REGION]` | `us-east-1` | AWS Region |
| `[AWS_ACCOUNT_ID]` | `123456789012` | AWS account number |
| `[DOMAIN_NAME]` | `launchboard.example.com` | Public domain for the app |
| `[EMAIL]` | `admin@example.com` | Email for SSL and alerts |
| `[IMAGE_TAG]` | `git-sha` | Immutable Docker image version |
| `[DB_PASSWORD]` | strong password | PostgreSQL password stored as a secret |

## Deployment Order

Most production systems start in dependency order:

1. Database
2. Database migrations
3. Backend API
4. Frontend UI
5. Monitoring and alerts
6. Security controls
7. Release strategy and recovery automation

The files in this directory follow that order using Compose health checks, Kubernetes probes, rollout waits, Swarm update settings, and CI/CD scripts.

## Quick Start For A Local Demo

```bash
cd deployment/phase-4-docker-compose
cp .env.example .env
./scripts/init-db.sh
docker compose up -d --build
./scripts/health-check.sh
```

Expected result:

```text
All services become healthy
Backend: http://localhost:8000/health
Frontend: http://localhost:8080
```

## Cost Warning

Local Docker and local Kubernetes are usually free. AWS labs can create real charges for EKS clusters, EC2 nodes, NAT gateways, load balancers, EBS volumes, snapshots, S3 buckets, CloudWatch logs, and Secrets Manager secrets. Always use AWS Budgets and destroy resources after class.

## Recommended Teaching Flow

For beginners, spend more time on phases 0, 3, 4, and 6. For intermediate students, focus on phases 7, 8, 9, and 10. For production-readiness discussions, use phases 11 and 12.

## Core Documentation URLs

- FastAPI deployment: https://fastapi.tiangolo.com/deployment/
- Docker: https://docs.docker.com/
- Docker Compose: https://docs.docker.com/compose/
- Docker Swarm: https://docs.docker.com/engine/swarm/
- Kubernetes: https://kubernetes.io/docs/
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS EKS: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html
- Prometheus: https://prometheus.io/docs/introduction/overview/
- Grafana: https://grafana.com/docs/
- HashiCorp Vault: https://developer.hashicorp.com/vault/docs
- Velero: https://velero.io/docs/
