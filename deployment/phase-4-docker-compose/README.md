# Phase 4: Docker Compose Full Stack

## Easy Explanation

This phase teaches how to run a complete N-tier application on one host with service names, private networks, persistent volumes, health checks, migrations, and startup ordering.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`docker-compose.yml` runs PostgreSQL, migration job, backend, and frontend. `docker-compose.prod.yml` adds production restart/resource settings. `.env.example` documents required values. `scripts/` handles init, migration, and health checks.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Usually free locally. On a cloud VM, the VM and disk continue charging until stopped or deleted.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-4-docker-compose
cp .env.example .env
./scripts/init-db.sh
docker compose up -d --build
./scripts/migrate.sh
./scripts/health-check.sh
docker compose ps
```

## Expected Output

`docker compose ps` shows healthy DB, backend, and frontend. `http://localhost:8080` opens the UI and `http://localhost:8000/ready` confirms database connectivity.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If the backend is unhealthy, check `docker compose logs launchboard-backend`. If migrations fail, check `DATABASE_URL` and PostgreSQL health. If the UI cannot call the API, check frontend proxy and `VITE_API_URL`.

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

Move to Phase 5 to convert the same service idea into Swarm orchestration.
