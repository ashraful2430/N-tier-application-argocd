# Incident Response Runbook

## First Five Minutes

1. Name the incident.
2. Assign incident commander.
3. Assign scribe.
4. Freeze deployments.
5. Check the public app URL.
6. Check Kubernetes pods and events.

## Investigation Commands

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp
kubectl -n devops-launchboard logs deploy/launchboard-backend
kubectl -n devops-launchboard logs deploy/launchboard-frontend
velero backup get
```

## Stabilization Choices

- Restart failed pods.
- Roll back the latest deployment.
- Restore from Velero backup.
- Restore PostgreSQL from dump.
- Recreate the cluster if the cluster is unrecoverable.

## Closeout

1. Confirm app access.
2. Confirm API health.
3. Confirm database reads and writes.
4. Record timestamps.
5. Write a post-incident review.
