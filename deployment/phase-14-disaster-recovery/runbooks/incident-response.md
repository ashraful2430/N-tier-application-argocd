# Incident Response Runbook

## First Response

1. Assign an incident commander.
2. Assign a scribe.
3. Freeze deployments.
4. Confirm user impact.
5. Check app, cluster, and backup status.

## Commands

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
kubectl -n devops-launchboard logs deploy/launchboard-backend --tail=100
velero backup get
velero restore get
```

## Recovery Choices

- Restart pods when only a pod failed.
- Roll back deployment when a new release caused the issue.
- Restore PostgreSQL dump when data is damaged.
- Restore Velero backup when Kubernetes resources or volumes are damaged.
- Rebuild the cluster when the cluster is unrecoverable.
