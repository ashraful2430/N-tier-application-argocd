# Phase 15: Performance And Load Validation

## Fresh Start Assumption

This phase will start from a fresh AWS or Kubernetes environment.

This phase will deploy the N-tier application and validate it with controlled performance and load tests.

## Purpose

This final phase exists so students can prove that a deployment is not only running, but also healthy under traffic.

The full guide will later include:

- Fresh deployment setup
- GitHub SSH key setup
- Frontend and backend clone
- Production image build
- Kubernetes or EKS deployment
- Metrics setup
- k6 installation
- Smoke test
- Load test
- Stress test
- Soak test
- HPA verification
- PostgreSQL resource observation
- Performance report
- Tuning notes
- Rollback decision
- Cleanup

## Expected Application Shape

```text
k6 load generator
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

Metrics
  |
  +-- pod CPU
  +-- pod memory
  +-- request latency
  +-- error rate
  +-- autoscaling behavior
```

## Files Planned For This Phase

```text
phase-15-performance-and-load-validation/
+-- README.md
+-- reports/
+-- tests/
    +-- k6/
```

Detailed commands and file contents will be added when we build this phase.
