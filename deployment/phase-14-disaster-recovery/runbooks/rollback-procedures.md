# Rollback Procedures

## Standard Kubernetes Deployment

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

## Frontend Deployment

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-frontend
kubectl -n devops-launchboard rollout undo deployment/launchboard-frontend
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend
```

## Database Restore

Use rollback only when schema/data damage is confirmed and the team accepts the RPO impact.

```bash
kubectl -n devops-launchboard exec -it deploy/launchboard-db -- psql -U launchboard_user -d launchboard
```
