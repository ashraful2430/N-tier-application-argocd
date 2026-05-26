# Rollback Procedures

Use Kubernetes rollout undo for standard releases, Argo Rollouts abort for canaries, and blue-green service selector switching for color deployments. Verify `/health`, `/ready`, and frontend `/healthz` after rollback.
