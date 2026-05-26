# Phase 7: CI/CD Automation

## Easy Explanation

This phase teaches how teams automate repeatable delivery: linting, tests, frontend builds, image scans, image pushes, Kubernetes rollout, and rollback workflows.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`Jenkinsfile` provides a Jenkins pipeline. `.github/workflows/` contains GitHub Actions workflows. `scripts/` contains reusable CI commands.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

GitHub Actions has free minutes with limits. Jenkins cost depends on where it runs. Docker registry storage and cloud deploy targets may charge.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-7-cicd
./scripts/run-tests.sh
./scripts/scan-image.sh [IMAGE]
./scripts/deploy.sh [IMAGE_TAG]
```

## Expected Output

Tests and linting pass, Docker image scan exits cleanly, and Kubernetes rollout status completes before the pipeline finishes.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If CI passes locally but fails in the runner, check missing secrets, AWS OIDC configuration, working directory, and tool versions. If rollout hangs, inspect Kubernetes events.

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

Move to Phase 8 to provision the Kubernetes platform on AWS.
