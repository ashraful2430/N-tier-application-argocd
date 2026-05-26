# Phase 8: Amazon EKS

## Easy Explanation

This phase teaches managed Kubernetes on AWS: Terraform state, IAM roles, node groups, security groups, kubeconfig, AWS Load Balancer Controller, and app deployment to EKS.

## What This Phase Teaches

- How this deployment style works in real production teams.
- Which files control infrastructure, application runtime, networking, and verification.
- How to validate success with simple commands instead of guessing.
- How to clean up resources so students do not create surprise bills.

## Files In This Phase

`terraform/` provisions EKS resources, `terraform.tfvars.example` shows required variables, `k8s/` contains application manifests, and `scripts/` automates cluster/app setup.

## Prerequisites

Complete `../phase-0-setup/prerequisites.md` first. Replace `[PROJECT_NAME]`, `[REGION]`, `[AWS_ACCOUNT_ID]`, `[DOMAIN_NAME]`, `[EMAIL]`, `[IMAGE_TAG]`, and `[DB_PASSWORD]` before running commands that use them.

## Cost And Free-Tier Notes

EKS has an hourly cluster control-plane charge. Worker nodes, load balancers, EBS volumes, NAT gateways, CloudWatch logs, and data transfer can add significant cost.

Always use AWS Budgets for cloud labs: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Step-By-Step Commands

```bash
cd deployment/phase-8-eks
cp terraform.tfvars.example terraform/terraform.tfvars
./scripts/deploy-eks.sh
./scripts/setup-alb-controller.sh
./scripts/configure-rbac.sh
./scripts/deploy-app.sh
kubectl -n devops-launchboard get ingress
```

## Expected Output

Terraform creates the cluster, kubeconfig points to EKS, backend rollout succeeds, and Ingress eventually receives an AWS load balancer address.

## Verification Checklist

- Required files exist in this phase directory.
- Secrets are not committed with real values.
- Health checks pass before moving to the next phase.
- Logs show normal startup with no repeated crash loops.
- Cloud resources, if any, have project and owner tags.

## Troubleshooting

Terraform failures usually involve IAM permissions, subnet tags, or missing variables. Load balancer failures usually involve controller IAM policy or subnet discovery tags.

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

Move to Phase 9 to observe the running platform.
