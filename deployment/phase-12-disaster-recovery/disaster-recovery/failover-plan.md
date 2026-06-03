# Failover Plan

## Purpose

This plan tells the student what to do when the primary app path is unhealthy.

## Recovery Targets

- RTO: restore public app access within 30 minutes for the lab.
- RPO: lose no more than the latest verified backup window.

## Steps

1. Freeze deployments.
2. Assign incident commander and scribe.
3. Confirm whether the failure is frontend, backend, database, node, or cluster level.
4. Check current backups with `velero backup get`.
5. Export a fresh database dump if the database is still reachable.
6. Restore Kubernetes resources from Velero if namespace resources are damaged.
7. Restore PostgreSQL data from dump if the database content is damaged.
8. Restart backend pods.
9. Verify `/health`, `/ready`, frontend `/healthz`, and browser access.
10. Record the recovery time and data-loss estimate.
