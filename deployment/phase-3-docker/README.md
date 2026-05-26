# Phase 3: Docker Images

## Easy Explanation

This phase teaches image design: multi-stage builds, small Alpine bases, non-root runtime users, health checks, Docker ignore rules, registry login, image tags, and vulnerability scanning.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`Dockerfile.backend` builds the FastAPI image, `Dockerfile.frontend` builds the Vite/Nginx image, `.dockerignore` keeps images clean, `build-and-push.sh` publishes images, and `docker-scan.sh` blocks risky vulnerabilities.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Local builds are free. Pushing to ECR may create small storage charges after the free tier or when many images are retained.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-3-docker
./build-and-push.sh [AWS_ACCOUNT_ID] [REGION] [IMAGE_TAG]
./docker-scan.sh [AWS_ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/launchboard-backend:[IMAGE_TAG]
./docker-scan.sh [AWS_ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/launchboard-frontend:[IMAGE_TAG]
```

## Expected Output

Docker builds both images, ECR repositories exist, images are pushed with the requested tag, and Trivy exits successfully when no blocking HIGH or CRITICAL fixed vulnerabilities are found.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

Build failures usually come from wrong build context or dependency install errors. Push failures usually mean AWS login, region, or repository permissions are wrong.

Useful first commands:

```bash
curl -fsS http://localhost:8000/health
curl -fsS http://localhost:8000/ready
kubectl get pods -A
docker ps
```


## Useful URLs

- FastAPI deployment guide: https://fastapi.tiangolo.com/deployment/
- Docker documentation: https://docs.docker.com/
- Docker Compose documentation: https://docs.docker.com/compose/
- Kubernetes documentation: https://kubernetes.io/docs/
- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- AWS EKS user guide: https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html


## Cleanup

Stop containers, delete Kubernetes resources, or destroy Terraform-managed cloud resources when the lab is done. Confirm the AWS Billing dashboard does not show unexpected running resources.

## Next Step

Use these images in Phase 4 Docker Compose.
