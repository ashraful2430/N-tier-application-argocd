# Phase 5: Docker Swarm

## Easy Explanation

This phase teaches built-in Docker orchestration: overlay networks, replicated services, secrets, rolling updates, service rollback, and stack deployment.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`stack.yml` defines Swarm services, `secrets/db_password.example` shows the secret format, and scripts initialize Swarm, deploy, update, and rollback.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Free locally if using one machine. Cloud Swarm clusters charge for every VM and attached disk.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-5-docker-swarm
export DB_PASSWORD=[DB_PASSWORD]
./scripts/init-swarm.sh
./scripts/deploy-stack.sh
docker stack services devops-launchboard
./scripts/rolling-update.sh devops-launchboard_launchboard-backend [IMAGE]
./scripts/rollback.sh devops-launchboard_launchboard-backend
```

## Expected Output

`docker stack services` shows desired replicas running. Rolling update replaces tasks gradually, and rollback returns the service to the previous image.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If services stay pending, inspect `docker service ps`. If secrets fail, recreate `db_password`. If images cannot pull, log in to the registry on every Swarm node.

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

Move to Phase 6 to learn Kubernetes equivalents.
