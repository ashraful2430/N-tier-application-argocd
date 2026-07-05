# DevOps LaunchBoard Deployment Guide

This `deployment/` directory is the production deployment branch guide for the DevOps LaunchBoard N-tier application. It is written for students who are learning how a real project moves from a local machine to Docker, Kubernetes, AWS EKS, monitoring, security, release strategies, disaster recovery, performance validation, Terraform, and Ansible — ending with a production capstone that combines everything.

The application has three main services:

| Service | What It Does | Technology | Port | Health Check |
| --- | --- | --- | ---: | --- |
| `launchboard-frontend` | Browser UI for students and operators | Vite/React served by Nginx | `8080` in containers | `/healthz` |
| `launchboard-backend` | REST API and business logic | FastAPI/Uvicorn | `8000` | `/health`, `/ready` |
| `launchboard-db` | Persistent application data | PostgreSQL 16 | `5432` | `pg_isready` |

## How To Use This Directory

Start with `phase-0-setup`, then move phase by phase. Each phase has its own README, manifests, configuration files, and supporting folders. The goal is that a student can open one phase, read the README, create the required files manually, run the commands, and understand what happened.

## Phase Map

| Phase | Topic | Main Learning Outcome |
| --- | --- | --- |
| `phase-0-setup` | Workstation and cloud prep | Install tools, set naming rules, understand cost risk |
| `phase-01-local-baseline` | Local app baseline | Prove frontend, backend, and PostgreSQL work before cloud deployment |
| `phase-02-bare-metal` | EC2 without containers | Run app directly with Linux services and Nginx |
| `phase-03-docker` | Container images | Build secure, small, non-root images |
| `phase-04-docker-compose` | Single-host stack | Run DB, migrations, API, and UI together |
| `phase-05-docker-swarm` | Swarm orchestration | Deploy replicated services with secrets and rollback |
| `phase-06-kubernetes-local` | Local Kubernetes | Learn Deployments, Services, Ingress, PVC, HPA |
| `phase-07-cicd-self-hosted` | Automation | Three delivery models: GitHub Actions, Jenkins on EKS, and GitOps with ArgoCD |
| `phase-08-eks` | AWS Kubernetes | Provision EKS with eksctl and deploy app |
| `phase-09-infrastructure-as-code-terraform` | Infrastructure as code | Learn Terraform basics on one EC2, then a production VPC/ALB/ASG/RDS deployment with modules and remote state |
| `phase-10-configuration-management-ansible` | Configuration management | Learn Ansible basics on one server, then a production multi-tier rolling deployment with roles and Vault |
| `phase-11-observability` | Monitoring and logs | Add metrics, alerts, dashboards, logs, and traces |
| `phase-12-security` | Hardening | Apply RBAC, NetworkPolicy, Vault, SAST, image scanning |
| `phase-13-advanced-deployments` | Safer releases | Practice blue-green, canary, and feature flags |
| `phase-14-disaster-recovery` | Recovery | Back up, restore, test failover, and run incident playbooks |
| `phase-15-performance-and-load-validation` | Performance validation | Run smoke, load, stress, and soak tests before calling the app production-ready |
| `phase-16-production-capstone` | Production capstone | Combine EKS, RDS, security, autoscaling, monitoring, backups, and load validation into one production-grade deployment |

## Values Students Must Replace

| Placeholder | Example | Meaning |
| --- | --- | --- |
| `YOUR_AWS_REGION` | `us-east-1` | AWS Region |
| `YOUR_ACCOUNT_ID` | `123456789012` | AWS account number |
| `YOUR_ALB_DNS_NAME` | `launchboard-alb.example.aws` | Public load balancer URL |
| `YOUR_EC2_PUBLIC_IP` | `13.229.100.25` | EC2 public IP address |
| `CHANGE_ME_STRONG_PASSWORD` | strong password | PostgreSQL password stored as a secret |

## Deployment Order

Most production systems start in dependency order:

1. Database
2. Database migrations
3. Backend API
4. Frontend UI
5. Monitoring and alerts
6. Security controls
7. Release strategy and recovery automation

The files in this directory follow that order using Compose health checks, Kubernetes probes, rollout waits, Swarm update settings, and CI/CD workflow files.

## Quick Start For A Local Demo

```bash
cd deployment/phase-04-docker-compose
cp .env.example .env
vim .env
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
curl -fsS http://localhost/health
```

Expected result:

```text
All services become healthy
Backend through frontend proxy: http://localhost/health
Frontend: http://localhost
```

## Cost Warning

Local Docker and local Kubernetes are usually free. AWS labs can create real charges for EKS clusters, EC2 nodes, NAT gateways, load balancers, EBS volumes, snapshots, S3 buckets, CloudWatch logs, and Secrets Manager secrets. Always use AWS Budgets and destroy resources after class.

## Recommended Teaching Flow

For beginners, spend more time on phases 0, 1, 2, 3, 4, and 6. For intermediate students, focus on phases 7 and 8. For infrastructure automation, use phases 9 (Terraform) and 10 (Ansible). For production-readiness discussions, use phases 11 (observability), 12 (security), 13 (advanced deployments), 14 (disaster recovery), and 15 (performance). Finish with the phase 16 capstone, which combines everything.

## Core Documentation URLs

- FastAPI deployment: https://fastapi.tiangolo.com/deployment/
- Docker: https://docs.docker.com/
- Docker Compose: https://docs.docker.com/compose/
- Docker Swarm: https://docs.docker.com/engine/swarm/
- Kubernetes: https://kubernetes.io/docs/
- AWS EKS: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html
- Prometheus: https://prometheus.io/docs/introduction/overview/
- Grafana: https://grafana.com/docs/
- HashiCorp Vault: https://developer.hashicorp.com/vault/docs
- Velero: https://velero.io/docs/
