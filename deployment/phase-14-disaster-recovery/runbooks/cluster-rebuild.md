# Cluster Rebuild Runbook

## Purpose

Use this when the original EKS cluster cannot be recovered.

## Steps

1. Create a new EKS cluster with the same phase cluster file.
2. Install the AWS Load Balancer Controller.
3. Install Velero using the same S3 bucket.
4. Restore the `devops-launchboard` namespace from the latest verified backup.
5. Confirm PVCs are restored.
6. Confirm backend, frontend, and PostgreSQL pods are ready.
7. Update DNS if the ALB address changed.
8. Run browser and API verification.

## Verification

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get pvc
kubectl -n devops-launchboard get ingress
curl -I http://YOUR_ALB_DNS_NAME
```
