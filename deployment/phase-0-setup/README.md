# Phase 0: Project Setup And Discovery

## Fresh Start Assumption

You do not need to complete any previous phase before using this guide.

This phase starts from a fresh local machine or fresh cloud workstation.

This phase does not deploy the application.

This phase helps students understand the N-tier application before they run or deploy it.

Students read this README from GitHub in the browser. Do not assume the deployment folder already exists on the student's machine. Every file that must be created is shown inline immediately after the `vim` command that creates it.

## What This Phase Teaches

By completing this phase, students will learn:

- What services exist in the project.
- Which repository and branch should be used.
- Which ports the frontend, backend, and database use.
- Which environment variables are required.
- Which health endpoints prove the backend is alive.
- Which tools are required before local, Docker, EC2, Kubernetes, EKS, Terraform, GitOps, observability, security, recovery, and performance phases.
- Why a deployment engineer should inspect a project before deploying it.

## Project Architecture

The application is a 3-tier project:

```text
Browser
  |
  v
React/Vite frontend
  |
  v
FastAPI backend
  |
  v
PostgreSQL database
```

Service map:

| Service | Technology | Local Port | Purpose |
| --- | --- | ---: | --- |
| Frontend | React, TypeScript, Vite, Three.js | `5173` | Browser UI |
| Backend | Python 3.12, FastAPI, SQLAlchemy, Alembic | `8000` | API and business logic |
| Database | PostgreSQL | `5432` | Persistent data |

Important backend endpoints:

| Endpoint | Purpose |
| --- | --- |
| `/health` | Confirms the API process is running |
| `/ready` | Confirms the API can reach PostgreSQL |
| `/docs` | FastAPI Swagger documentation |
| `/api/summary` | Application summary data |
| `/api/services` | Service list |
| `/api/deployments` | Deployment records |

## Architecture Decision Guide

This phase has no architecture to choose — but the habits in it are how real teams operate from day one:

- **Every company you join has a version of this phase.** It is called the onboarding doc, the "dev environment setup" wiki page, or the platform team's bootstrap guide. Sloppy ones cost every new hire a lost week; good ones get you shipping on day two. Learning to *follow* one precisely — and later to *write* one — is a genuine job skill.
- **Naming conventions and tagging are not bureaucracy.** In a real AWS account with 40 engineers, the difference between `devops-launchboard-phase-2` and `test-instance-3` is whether the cost report means anything and whether anyone dares delete a resource.
- **Budgets before resources** is how professionals treat any cloud account, personal or corporate. The engineer who sets a billing alarm before their first `terraform apply` is the one who never has the $3,000-surprise story.

## Cost Warning

This phase is usually free.

It does not create AWS resources.

Cost can begin only if you later create cloud resources such as EC2, EBS, NAT Gateway, ALB, EKS, S3, or ECR.

Before cloud phases:

- Create an AWS Budget alert.
- Use one AWS region.
- Clean up all resources after labs.
- Never leave EKS, NAT Gateway, or Load Balancers running by accident.

Reference:

- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- AWS Pricing Calculator: https://calculator.aws/

## Repository

Project repository:

```text
git@github.com:Ashik-DevOps-Class/N-tier-application.git
```

Recommended branch:

```text
main
```

Why:

Students should work from the normal application branch. Deployment files are created manually by following each phase README.

## Step 1: Install Basic Discovery Tools

Run this command from: your local Ubuntu machine

```bash
sudo apt update
sudo apt install -y git curl vim jq tree ca-certificates
```

What each tool does:

- `git` clones the project.
- `curl` tests HTTP endpoints.
- `vim` creates and edits files manually.
- `jq` reads JSON responses.
- `tree` displays folder structure clearly.
- `ca-certificates` helps HTTPS connections work correctly.

Verify:

```bash
git --version
curl --version
vim --version
jq --version
tree --version
```

Expected result:

```text
Each command prints a version.
```

Reference:

- Git documentation: https://git-scm.com/doc
- curl documentation: https://curl.se/docs/
- jq manual: https://jqlang.github.io/jq/manual/

## Step 2: Create GitHub SSH Key

Run this command from: your local machine

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "ntier-launchboard-phase-0" -f ~/.ssh/ntier_launchboard_github_key
cat ~/.ssh/ntier_launchboard_github_key.pub
```

Add the public key to GitHub:

```text
GitHub
Settings
SSH and GPG keys
New SSH key
```

Use:

| Field | Value |
| --- | --- |
| Title | `ntier-launchboard-phase-0` |
| Key type | Authentication Key |
| Key | Paste the public key |

Why this step exists:

The machine that clones the repository needs GitHub access. SSH keys avoid passwords and are the standard way to clone private or protected repositories.

## Step 3: Configure SSH For GitHub

Run:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/ntier_launchboard_github_key
  IdentitiesOnly yes
```

Save with:

```text
:wq
```

Secure permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/ntier_launchboard_github_key
chmod 644 ~/.ssh/ntier_launchboard_github_key.pub
```

Test:

```bash
ssh -T git@github.com
```

Expected result:

```text
GitHub says authentication succeeded, but shell access is not provided.
```

Reference:

- GitHub SSH documentation: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 4: Clone The Project

Run:

```bash
sudo mkdir -p /opt/ntier-launchboard
sudo chown -R "$USER:$USER" /opt/ntier-launchboard
cd /opt/ntier-launchboard
git clone git@github.com:Ashik-DevOps-Class/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Expected output:

```text
main
```

Why this step exists:

Students need the real project code before discovering how it runs. `/opt/ntier-launchboard/app-source` gives the project a predictable folder location for later phases.

## Step 5: Inspect The Top-Level Project

Run:

```bash
cd /opt/ntier-launchboard/app-source
pwd
tree -L 2 -a
```

Expected folders:

```text
backend
frontend
deployment
docs
```

Why this step exists:

Deployment commands depend on folder names. Students should confirm the repository structure before copying commands.

## Step 6: Inspect Backend Configuration

Run:

```bash
cd /opt/ntier-launchboard/app-source
cat backend/pyproject.toml
cat backend/.env.example
cat backend/app/core/config.py
cat backend/app/api/health.py
```

What students should learn:

- Backend requires Python `>=3.12`.
- Backend uses FastAPI.
- Backend reads environment variables from `backend/.env`.
- Backend connects to PostgreSQL through `DATABASE_URL`.
- Backend allows browser origins through `CORS_ORIGINS`.
- `/health` checks API process health.
- `/ready` checks database connectivity.

Important backend variables:

| Variable | Purpose | Local Example |
| --- | --- | --- |
| `APP_NAME` | API display name | `DevOps LaunchBoard API` |
| `APP_ENV` | Environment label | `local` |
| `DATABASE_URL` | PostgreSQL async connection string | `postgresql+asyncpg://launchboard_user:launchboard_pass@localhost:5432/launchboard` |
| `CORS_ORIGINS` | Frontend origins allowed to call API | `http://localhost:5173` |
| `SEED_DEMO_DATA` | Adds demo rows on startup | `true` |

## Step 7: Inspect Frontend Configuration

Run:

```bash
cd /opt/ntier-launchboard/app-source
cat frontend/package.json
cat frontend/.env.example
cat frontend/src/lib/api.ts
cat frontend/vite.config.ts
```

What students should learn:

- Frontend uses Vite and React.
- Frontend development server listens on port `5173`.
- Frontend reads `VITE_API_URL`.
- Browser API calls go to the backend URL configured in `frontend/.env`.

Important frontend variable:

| Variable | Purpose | Local Example |
| --- | --- | --- |
| `VITE_API_URL` | Backend API URL used by browser code | `http://localhost:8000` |

Reference:

- Vite environment variables: https://vite.dev/guide/env-and-mode
- Vite server options: https://vite.dev/config/server-options

## Step 8: Create Project Discovery Notes

Create a local notes folder:

```bash
mkdir -p /opt/ntier-launchboard/discovery
cd /opt/ntier-launchboard/discovery
vim project-discovery.md
```

Paste:

````markdown
# N-tier LaunchBoard Project Discovery

## Repository

Repository:

```text
git@github.com:Ashik-DevOps-Class/N-tier-application.git
```

Branch:

```text
main
```

## Services

| Service | Technology | Port | Health |
| --- | --- | ---: | --- |
| Frontend | React, TypeScript, Vite | 5173 | Browser page |
| Backend | Python 3.12, FastAPI | 8000 | /health and /ready |
| Database | PostgreSQL | 5432 | pg_isready |

## Environment Variables

Backend:

```text
APP_NAME
APP_ENV
DATABASE_URL
CORS_ORIGINS
SEED_DEMO_DATA
```

Frontend:

```text
VITE_API_URL
```

## Deployment Risks

- PostgreSQL must be ready before backend readiness passes.
- Frontend must use the correct backend URL.
- CORS must include the frontend origin.
- Python must be 3.12 or newer.
- Secrets must not be committed.
- Cloud resources must be deleted after labs.

## Verification Commands

```bash
curl -s http://localhost:8000/health
curl -s http://localhost:8000/ready
curl -I http://localhost:5173
```
````

Save with:

```text
:wq
```

Why this file exists:

Deployment notes force students to write down what they discovered. This prevents random guessing in later phases.

## Step 9: Tool Checklist For Later Phases

Later phases will use these tools:

| Tool | Used In |
| --- | --- |
| Python 3.12 | Backend local run and image builds |
| Node.js 22 | Frontend local run and image builds |
| PostgreSQL | Local database and production-style database |
| Docker | Container phases |
| Docker Compose | Single-server full stack |
| kubectl | Kubernetes phases |
| Helm | Kubernetes add-ons |
| Terraform | Infrastructure as code |
| AWS CLI | AWS resource creation |
| eksctl | EKS cluster creation |
| Trivy | Image scanning |
| k6 | Performance validation |

## Troubleshooting

### Problem: GitHub SSH Fails

Check:

```bash
ssh -T git@github.com
cat ~/.ssh/config
ls -la ~/.ssh
```

Common causes:

```text
Public key was not added to GitHub.
SSH config points to the wrong key.
Private key permissions are too open.
```

### Problem: Folder Structure Looks Different

Check:

```bash
git remote -v
git branch --show-current
find . -maxdepth 2 -type d | sort
```

Common causes:

```text
Wrong repository cloned.
Wrong branch checked out.
Repository changed after this guide was written.
```

## Cleanup

Phase 0 does not create cloud resources.

To remove local discovery files:

```bash
sudo rm -rf /opt/ntier-launchboard
```

Only run cleanup when you are done with local notes and cloned source.

## What To Do Next

Move to:

```text
Phase 1: Local Baseline
```

Why:

Phase 0 identifies how the project works. Phase 1 proves the project actually runs locally.
