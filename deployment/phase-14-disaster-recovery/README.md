# Phase 14: Disaster Recovery

## Fresh Start Assumption

This phase will start from a fresh AWS or Kubernetes environment.

This phase will deploy the N-tier application and then teach backup, restore, rollback, incident response, and recovery drills.

## Purpose

This phase exists so students learn that production deployment is not complete until the team can recover after failure.

The full guide will later include:

- Fresh AWS or Kubernetes setup
- GitHub SSH key setup
- Frontend and backend clone
- Production image build
- Kubernetes or EKS deployment
- PostgreSQL backup plan
- Velero or platform backup setup
- Manual backup
- Scheduled backup
- Restore drill
- Cluster rebuild recovery path
- Incident response runbook
- Recovery checklist
- Rollback procedures
- Cleanup

## Expected Application Shape

```text
User Browser
  |
  v
Nginx, ALB, or Ingress
  |
  v
Frontend
  |
  v
Backend API
  |
  v
PostgreSQL database

Backup system
  |
  +-- application manifests
  +-- database data
  +-- persistent volumes
  +-- recovery runbooks
```

## Files Planned For This Phase

```text
phase-14-disaster-recovery/
+-- README.md
+-- aws/
+-- backups/
+-- runbooks/
+-- velero/
```

Detailed commands and file contents will be added when we build this phase.
