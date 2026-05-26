# Phase 11: Advanced Deployment Strategies

## Easy Explanation

This phase teaches release safety. Students compare blue-green deployments, canary releases, and feature flags so production changes can be tested with controlled traffic and fast rollback.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`blue-green/` contains blue and green deployments plus traffic switch scripts, `canary/` contains Argo Rollouts resources, `feature-flags/` contains runtime flag config, and `scripts/` automates rollout starts.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Mostly cluster compute cost. Running blue and green together doubles backend capacity during the release window. Canary tools may add controller pods.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-11-advanced-deployments
./scripts/deploy-blue-green.sh
./blue-green/switch-traffic.sh green
./blue-green/rollback.sh
./scripts/deploy-canary.sh
./canary/monitor-canary.sh
```

## Expected Output

Blue and green deployments run side by side, service selector controls active traffic, and canary rollout gradually increases traffic weight.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If traffic does not switch, inspect the Service selector and pod labels. If Argo commands fail, install Argo Rollouts controller and kubectl plugin.

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

Move to Phase 12 to prepare for incidents and data loss.
