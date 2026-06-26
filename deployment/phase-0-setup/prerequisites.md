# Phase 0 Prerequisites

This file is the quick checklist for the N-tier LaunchBoard deployment curriculum.

Use the main Phase 0 README for full step-by-step instructions.

## Required Accounts

- GitHub account
- AWS account for later cloud phases

## Required Local Tools For Phase 0

```bash
git --version
curl --version
vim --version
jq --version
tree --version
```

## Required Tools For Later Phases

```bash
python3 --version
node --version
npm --version
docker --version
docker compose version
kubectl version --client
helm version
aws --version
terraform version
eksctl version
trivy --version
k6 version
```

## Recommended Versions

| Tool | Recommended Version |
| --- | --- |
| Ubuntu | 24.04 LTS |
| Python | 3.12 or newer |
| Node.js | 22 LTS |
| PostgreSQL | 16 or newer |
| Docker | Current stable engine |
| Docker Compose | v2 |
| kubectl | Match cluster minor version |
| Helm | v3 |
| Terraform | 1.8 or newer |
| AWS CLI | v2 |

## Project Defaults

| Item | Value |
| --- | --- |
| Project name | `devops-launchboard` |
| Repository | `git@github.com:ashraful2430/N-tier-application.git` |
| Frontend local port | `5173` |
| Backend local port | `8000` |
| PostgreSQL port | `5432` |
| Backend health | `/health` |
| Backend readiness | `/ready` |

## Suggested Environment Variables For Labs

```bash
export PROJECT_NAME=devops-launchboard
export AWS_REGION=us-east-1
export DOMAIN_NAME=launchboard.example.com
export ADMIN_EMAIL=student@example.com
```

## Cost Safety

Before AWS phases:

- Create an AWS Budget alert.
- Use one AWS region.
- Tag resources with project and owner.
- Delete resources after practice.
- Watch for NAT Gateway, EKS, Load Balancer, EBS, S3, and ECR charges.

Reference:

- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- AWS Pricing Calculator: https://calculator.aws/