# Phase 9: Observability

## Easy Explanation

This phase teaches the three pillars of observability: metrics, logs, and traces. Students learn how alerts and dashboards support production operations.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`prometheus/` has scrape and alert rules, `grafana/` has datasource and dashboard provisioning, `elk-stack/` has log collector configs, `jaeger/` has tracing manifests, and scripts deploy/verify monitoring.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Local monitoring costs CPU, memory, and disk. Cloud monitoring can charge for logs, metrics, storage, and managed services.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-9-observability
./scripts/deploy-monitoring.sh
./scripts/verify-metrics.sh
kubectl -n observability get pods
```

## Expected Output

Prometheus health endpoint is reachable, Jaeger pods deploy, and Grafana has a Prometheus datasource ready for dashboards.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

If metrics are missing, check scrape targets and service names. If logs are missing, verify container log paths. If dashboards are empty, check datasource URL and time range.

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

Move to Phase 10 to harden what you can now observe.
