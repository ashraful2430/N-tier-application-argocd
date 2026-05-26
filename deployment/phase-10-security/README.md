# Phase 10: Security Hardening

## Easy Explanation

This phase teaches defense-in-depth: image scanning, RBAC, NetworkPolicy, namespace pod security labels, Vault policies, Sealed Secrets, AWS Secrets Manager, and SAST.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`vault/` contains Vault config and policy, `k8s-security/` contains Kubernetes controls, `secrets-management/` shows sealed and cloud secrets, `sast/` provides scanning configs, and scripts apply controls.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

Vault, SonarQube, and scanners can run locally, but cloud secret storage, nodes, and logs may charge. SonarQube needs noticeable memory.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-10-security
./scripts/scan-images.sh [IMAGE]
./scripts/setup-rbac.sh
./scripts/setup-vault.sh
kubectl -n devops-launchboard get role,rolebinding,networkpolicy
```

## Expected Output

Image scan passes, RBAC resources exist, NetworkPolicy is applied, and Vault has the expected secret engine/policy.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

NetworkPolicy may block traffic if labels do not match. Vault setup fails if `VAULT_ADDR` or tokens are missing. SAST regex rules should be tuned to reduce false positives.

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

Move to Phase 11 to release changes with safer rollout patterns.
