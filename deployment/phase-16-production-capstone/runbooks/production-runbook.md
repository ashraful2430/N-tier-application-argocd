# Production Runbook: DevOps LaunchBoard

## Quick Facts

| Item | Value |
| --- | --- |
| Cluster | `devops-launchboard-phase-16` (EKS) |
| App namespace | `devops-launchboard` |
| Observability namespace | `observability` |
| Backup namespace | `velero` |
| Entry point | ALB DNS name (`kubectl -n devops-launchboard get ingress`) |
| Image registry | ECR `launchboard-backend` / `launchboard-frontend` |
| Database | Amazon RDS PostgreSQL `launchboard-phase-16` (private, cluster-SG only) |
| Backups | Velero daily 03:00 UTC (k8s objects) + RDS automated daily snapshots and PITR (data) |

## First Response To Any Incident

```bash
kubectl -n devops-launchboard get pods -o wide
kubectl -n devops-launchboard get events --sort-by=.lastTimestamp | tail -20
kubectl -n devops-launchboard get ingress
kubectl top nodes && kubectl top pods -n devops-launchboard
```

Decide which situation below matches, then follow it.

## Situation 1: App Unreachable (browser timeout or 5xx from ALB)

1. Ingress has an address? `kubectl -n devops-launchboard get ingress` — if empty, check the ALB controller: `kubectl -n kube-system logs deployment/aws-load-balancer-controller --tail=50`.
2. Frontend pods Ready? `kubectl -n devops-launchboard get pods -l app=launchboard-frontend`.
3. Target health in AWS: EC2 Console > Target Groups > select > Targets.
4. If pods are Ready but targets unhealthy, a NetworkPolicy or security-group change is the usual suspect — verify `allow-frontend-from-anywhere` exists: `kubectl -n devops-launchboard get networkpolicy`.

## Situation 2: Backend CrashLoopBackOff

```bash
kubectl -n devops-launchboard logs deployment/launchboard-backend --previous --tail=50
```

- `connection refused` to the DB: check Situation 3.
- Migration/schema errors: check the last migration Job: `kubectl -n devops-launchboard logs job/launchboard-migrate`.
- OOMKilled (`kubectl -n devops-launchboard describe pod ... | grep -A3 "Last State"`): raise the memory limit in the backend Deployment and apply.

## Situation 3: Database Down Or Data Problem

```bash
aws rds describe-db-instances --db-instance-identifier launchboard-phase-16 \
  --query 'DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone}' --output table
```

- Status not `available`: check RDS Console > Events for the instance (failover, maintenance, storage full).
- Status `available` but backend cannot connect: verify the DB security group still allows 5432 from the cluster SG, and that `DB_HOST` in the ConfigMap matches the current endpoint.
- Bad data / bad migration: restore from an RDS snapshot or point-in-time recovery — this creates a NEW instance; update `DB_HOST` and `DATABASE_URL` to its endpoint, then restart the backend (Situation 6 flow, but for the DB endpoint).
- CPU/connection pressure: RDS Console > Monitoring; `db.t3.micro` is a lab size — scaling the instance class is a modify-and-reboot operation.

## Situation 4: Rollback A Bad Deployment

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Same commands for `launchboard-frontend`. Verify with `curl http://ALB_DNS/health`.

## Situation 5: Restore From Backup

List restore points:

```bash
velero backup get
```

Restore the namespace (destructive to current state — confirm with a second person in a real team):

```bash
kubectl delete namespace devops-launchboard
velero restore create --from-backup BACKUP_NAME --wait
velero restore describe RESTORE_NAME
kubectl -n devops-launchboard get pods
```

No volume restore is involved — the data lives in RDS, which namespace deletion never touched; the app reconnects to it as Pods come up. The ALB is recreated by the controller — the DNS name changes, so update `CORS_ORIGINS` in the ConfigMap and restart the backend (see Situation 6).

## Situation 6: ALB DNS Changed (after restore or Ingress recreation)

```bash
ALB_DNS=$(kubectl -n devops-launchboard get ingress launchboard-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl -n devops-launchboard patch configmap launchboard-config -p "{\"data\":{\"CORS_ORIGINS\":\"http://${ALB_DNS}\"}}"
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

## Situation 7: Node Or Capacity Problems

```bash
kubectl get nodes
kubectl describe node NODE_NAME | grep -A5 "Conditions"
```

- Node NotReady: EKS managed node groups replace it automatically; watch for 5-10 minutes.
- Pods Pending for capacity: scale the node group:

```bash
eksctl scale nodegroup --cluster devops-launchboard-phase-16 --name launchboard-workers --nodes 3 --region $AWS_REGION
```

## Weekly Checks

```text
[ ] velero backup get - last daily backup Completed
[ ] aws rds describe-db-snapshots shows yesterday's automated snapshot
[ ] One test restore performed this month
[ ] Grafana: no sustained CPU > 80% or memory > 85% on nodes
[ ] kubectl get pods -A | grep -v Running - investigate anything else
[ ] ECR scan findings reviewed (Console > ECR > repository > images)
[ ] AWS Budget still within expectations
```
