# Failover Plan

1. Confirm incident scope and freeze deployments.
2. Promote a healthy replica or restore the latest verified snapshot.
3. Update `DATABASE_URL` in the secret manager and Kubernetes secret.
4. Restart backend pods and verify `/ready`.
5. Communicate recovery status and record timestamps.
