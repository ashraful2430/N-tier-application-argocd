# Phase 6: Local Kubernetes

## Easy Explanation

This phase teaches core Kubernetes objects: Namespace, ConfigMap, Secret, PVC, Deployment, Job, Service, Ingress, HPA, probes, resources, and Kustomize.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`k8s/` contains manifests and `kustomization.yaml`. `scripts/deploy.sh` applies everything, `test-local.sh` verifies the frontend through port-forward, and `cleanup.sh` removes resources.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Usually free on Docker Desktop, Kind, Minikube, or k3d. Watch local CPU, memory, and disk usage.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-6-kubernetes-local
./scripts/deploy.sh
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get svc
./scripts/test-local.sh
```

## Expected Output

Pods reach `Running` or `Completed`, deployments become available, and the frontend health endpoint responds through port-forward.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

Use `kubectl describe pod` for scheduling and probe failures. Use `kubectl logs` for app errors. If Ingress does not work locally, use port-forward first.

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

Move to Phase 7 to automate testing and deployment.
