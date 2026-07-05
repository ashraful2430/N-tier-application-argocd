# Performance Report

## Test Context

| Item | Value |
| --- | --- |
| Date |  |
| Tester |  |
| AWS Region |  |
| Cluster Name | devops-launchboard-phase-15 |
| Backend Image Tag | phase-15 |
| Frontend Image Tag | phase-15 |
| Test Tool | k6 |

## Environment

| Component | Configuration |
| --- | --- |
| EKS Nodes |  |
| Backend Replicas |  |
| Frontend Replicas |  |
| HPA Min/Max |  |
| Database | PostgreSQL pod with EBS PVC |

## Results

| Test | Target Load | p95 Latency | p99 Latency | Error Rate | Pass/Fail |
| --- | ---: | ---: | ---: | ---: | --- |
| Smoke | 1 VU |  |  |  |  |
| Load | 20 VUs |  |  |  |  |
| Stress | 100 VUs |  |  |  |  |
| Soak | 15 VUs for 30m |  |  |  |  |

## Observations

```text
Write what changed during the test.
Example: backend HPA scaled from 2 pods to 4 pods after CPU increased.
```

## Bottlenecks

```text
Write the slowest part of the system.
Example: backend CPU reached 90 percent before HPA added pods.
```

## Tuning Actions

```text
Write what you changed after the test.
Example: increased backend memory limit from 512Mi to 768Mi.
```

## Final Decision

```text
Pass or fail the deployment for production-like traffic.
```
