# RTO And RPO

## RTO

Recovery Time Objective means how long the app is allowed to be unavailable.

For this lab:

```text
RTO = 30 minutes
```

## RPO

Recovery Point Objective means how much data the app is allowed to lose.

For this lab:

```text
RPO = 24 hours for Velero scheduled backups
RPO = near current time when a fresh PostgreSQL dump exists
```

## Why This Matters

Backup tools are not enough by themselves. Students must know how fast they need to recover and how much data loss is acceptable before choosing a backup schedule.
