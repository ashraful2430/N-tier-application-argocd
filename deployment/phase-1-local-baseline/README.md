# Phase 1: Local Baseline

## Fresh Start Assumption

This phase will start from a fresh local Ubuntu machine or local development environment.

This phase will run the N-tier application locally before any AWS, Docker, Kubernetes, CI/CD, observability, security, release, recovery, or performance phase.

## Purpose

This phase exists so students can prove the app works before deploying it anywhere else.

The full guide will later include:

- Tool installation from scratch
- GitHub SSH key setup
- Frontend clone
- Backend clone
- Local PostgreSQL setup
- Backend environment file
- Frontend environment file
- Backend local run command
- Frontend local run command
- Health checks
- Troubleshooting
- Cleanup

## Expected Application Shape

```text
Browser
  |
  v
Frontend local server
  |
  v
Backend local API
  |
  v
PostgreSQL database
```

## Files Planned For This Phase

```text
phase-1-local-baseline/
+-- README.md
+-- env/
+-- notes/
```

Detailed commands and file contents will be added when we build this phase.
