# Phase 12: Disaster Recovery

## Easy Explanation

This phase teaches backup and recovery thinking: RDS backups, Velero Kubernetes backups, restore tests, multi-AZ planning, failover procedures, chaos experiments, and incident runbooks.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`backup/` contains RDS and Velero backup assets, `disaster-recovery/` contains multi-AZ and failover files, `chaos-engineering/` contains LitmusChaos experiments, and `runbooks/` contains incident procedures.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Backups, snapshots, standby databases, object storage, and extra nodes can charge continuously. Multi-AZ databases cost more than single-AZ databases.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-12-disaster-recovery
./backup/scripts/backup-now.sh
./backup/scripts/restore-db.sh [BACKUP_NAME]
./disaster-recovery/test-failover.sh
./chaos-engineering/run-chaos-tests.sh
```

## Expected Output

Manual backups are created, restore jobs start successfully, backend recovers after restart/failover testing, and runbooks give clear incident steps.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If restore fails, verify backup name, Velero storage location, and namespace. If chaos tests fail to run, verify LitmusChaos CRDs and service account permissions.

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

Review the full platform and have students perform a game-day exercise using the runbooks.
