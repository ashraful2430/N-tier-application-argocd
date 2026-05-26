# phase-6-kubernetes-local

## Overview

Phase 6 deploys the app to a local Kubernetes cluster.

## Prerequisites And Costs

Complete `../phase-0-setup/prerequisites.md`. Local phases use local CPU, memory, and disk. AWS phases may create billable EC2 instances, EKS clusters, load balancers, NAT gateways, EBS volumes, S3 buckets, snapshots, CloudWatch logs, and Secrets Manager secrets. Configure AWS Budgets before cloud labs and clean up at the end.

## Commands

```bash
cd deployment/phase-6-kubernetes-local
find . -maxdepth 3 -type f | sort
```

Replace placeholders before execution: `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, `[DB_PASSWORD]`.

## Verification

```bash
curl -fsS http://localhost:8000/health
curl -fsS http://localhost:8000/ready
curl -fsS http://localhost:8080/healthz
```

## Troubleshooting

Check logs first, then verify `DATABASE_URL`, `CORS_ORIGINS`, image tags, DNS, security groups, and database readiness. For Kubernetes, use `kubectl describe`, `kubectl logs`, and rollout status commands.

## Documentation

- https://fastapi.tiangolo.com/deployment/
- https://docs.docker.com/
- https://kubernetes.io/docs/
- https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html

## Cleanup And Next Step

Stop containers or destroy cloud resources before moving to the next phase. Continue when all health checks pass and expected cost alerts are configured.
