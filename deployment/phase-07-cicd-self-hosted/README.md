# Phase 7: CI/CD Automation

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server and a GitHub repository.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker is not installed yet.
- Kind and kubectl are not installed yet.
- The repository is not cloned yet.
- GitHub Actions workflows are not configured yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Build

This phase creates a CI/CD pipeline that:

- Runs backend lint and smoke checks.
- Runs frontend lint and build checks.
- Builds backend and frontend Docker images.
- Scans Docker images with Trivy.
- Optionally pushes images to GitHub Container Registry.
- Deploys the app to a local Kind Kubernetes cluster on an EC2 self-hosted GitHub Actions runner.
- Creates Kubernetes ConfigMap and Secret from GitHub Actions variable and secret values.
- Tags every deployment with the Git commit SHA so rollback is real, not cosmetic.
- Waits for rollout.
- Verifies the app with curl.
- Supports rollback through a manual GitHub Actions workflow.

## CI/CD Architecture

```text
Developer pushes to GitHub main
  |
  v
GitHub Actions hosted runner
  |
  | build-and-test (lint, smoke test, frontend build)
  | docker build + Trivy scan + optional push to GHCR
  v
GitHub Actions self-hosted runner on EC2
  |
  | Docker
  | Kind
  | kubectl
  v
Local Kubernetes cluster (Kind)
  |
  v
DevOps LaunchBoard app
```

## When To Use This Architecture

This is the least optional phase in the track — in real jobs, CI/CD is simply the water you swim in:

- **The team with manual deploys.** Someone SSHes to the server and runs commands from a wiki page; releases depend on that one person being awake. Building the first pipeline for such a team — tests, image build, scan, deploy on push — is one of the highest-impact things a junior engineer can do, and this phase is that build.
- **PR validation is table stakes everywhere.** Nearly every company gates merges on a green pipeline: lint, tests, image build, vulnerability scan. The workflows in this phase are the standard shape of that gate; on the job you will read, extend, and debug files exactly like them weekly.
- **GitHub-hosted teams (most teams).** Actions is the default choice when the code already lives on GitHub — zero CI infrastructure to run. Knowing its workflow syntax, secrets handling, and caching is directly hireable.
- **Testing Kubernetes manifests without a cluster bill.** The kind-in-CI trick — boot a throwaway cluster inside the pipeline, apply manifests, run smoke tests, discard — is how real teams validate k8s changes on every PR for free.

The sub-labs map to real employer profiles: `phase-7-cicd-EKS` (GitHub-native team deploying to cloud Kubernetes — the mainstream mid-size stack), `phase-7-cicd-jenkins` (enterprises and regulated industries running self-hosted CI), and `phase-7-gitops-argocd` (platform teams standardizing delivery via Git).

## Cost Warning

| Resource | Approximate Cost |
| --- | --- |
| 1 × t3.small EC2 (runs kind + the pipeline targets) | ~$0.02/hour |
| 20 GB gp3 EBS | ~$0.002/hour |
| GitHub Actions minutes | free for public repositories (2,000 min/month free tier for private) |
| Docker Hub | free tier (public repositories) |

The kind cluster is just containers on the one EC2 instance — no EKS, NAT, or load balancer charges in this parent lab. An 8-hour session costs well under $0.25. The `phase-7-cicd-EKS`, `phase-7-cicd-jenkins`, and `phase-7-gitops-argocd` sub-labs use real EKS clusters and carry their own (larger) cost warnings.

Create an AWS Budget before starting: AWS Console > Billing > Budgets > Create budget.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-7-runner` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-7-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if testing HTTPS |

Do not open:

```text
8000
5432
6443
```

The backend, database, and Kubernetes API should not be public.

## Files Included In This Phase

```text
deployment/phase-07-cicd-self-hosted/
+-- .github/
|   +-- workflows/
|       +-- build-and-test.yml          (teaching copy: CI checks)
|       +-- docker-build-push.yml       (teaching copy: build, scan, push images)
|       +-- deploy-k8s.yml              (teaching copy: deploy to Kind on the runner)
|       +-- rollback.yml                (teaching copy: manual rollback)
+-- k8s/
|   +-- namespace.yaml
|   +-- configmap.yaml
|   +-- secret.example.yaml
|   +-- pvc.yaml
|   +-- launchboard-postgres-deployment.yaml
|   +-- launchboard-postgres-service.yaml
|   +-- launchboard-migration-job.yaml
|   +-- launchboard-backend-deployment.yaml
|   +-- launchboard-backend-service.yaml
|   +-- launchboard-frontend-deployment.yaml
|   +-- launchboard-frontend-service.yaml
|   +-- ingress.yaml
|   +-- hpa.yaml
|   +-- kustomization.yaml
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- Jenkinsfile                          (optional: same pipeline expressed for Jenkins)
+-- kind-config.yaml
+-- nginx-frontend.conf
+-- README.md
```

Important: GitHub Actions only reads workflows from the root `.github/workflows/` folder of the repository. The copies inside `deployment/phase-07-cicd-self-hosted/.github/workflows/` are teaching copies so each phase folder is self-contained. You will create each workflow once and copy it to both locations.

## Step 1: Create EC2 Server

Run this step from AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-7-runner` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 30 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

Why this step exists:

The EC2 server will run Docker, Kind, kubectl, and the GitHub Actions self-hosted runner. The deployment workflow runs on this machine and deploys into the local Kind cluster. Note that the self-hosted runner makes only outbound connections to GitHub, so no inbound port needs to be opened for the runner itself.

Reference:

- AWS EC2 docs: https://docs.aws.amazon.com/ec2/
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 2: SSH Into EC2

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Verify:

```bash
whoami
hostname
pwd
```

Expected:

```text
ubuntu
ip-...
/home/ubuntu
```

## Step 3: Update Server And Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

Why this step exists:

The self-hosted runner needs normal Linux tools for cloning, Docker setup, file editing, and endpoint checks.

## Step 4: Install Docker

Run:

```bash
cd ~
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ubuntu
```

Log out and SSH back in so the docker group membership takes effect:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Verify:

```bash
docker --version
docker info
```

Why this step exists:

The deploy workflow builds images with Docker and runs Kind, which itself runs Kubernetes inside Docker containers. The `usermod -aG docker ubuntu` line matters for CI: the self-hosted runner process runs as the `ubuntu` user, and without docker group membership every `docker` command in the workflow would fail with a permission error.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Install Kubectl And Kind

Install kubectl:

```bash
cd ~
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
rm stable.txt
```

Install Kind:

```bash
cd ~
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/kind
```

Verify:

```bash
kubectl version --client
kind version
```

Why this step exists:

The deploy workflow uses `kind` to create a local Kubernetes cluster and `kubectl` to deploy the app. Both binaries must be in the PATH of the user running the self-hosted runner.

Reference:

- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- Kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/

## Step 6: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-7-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Add the public key to GitHub:

```text
GitHub repository
Settings
Deploy keys
Add deploy key
```

Create SSH config:

```bash
vim ~/.ssh/config
```

Paste:

```text
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/devops_launchboard_github_key
  IdentitiesOnly yes
```

Secure permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
```

Test:

```bash
ssh -T git@github.com
```

Why this step exists:

The deploy key lets the EC2 server clone the repository over SSH without a personal password or token. A deploy key is scoped to one repository, which is safer than a personal SSH key on a shared lab server.

Reference:

- GitHub deploy keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys

## Step 7: Clone The Repository

Run:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Expected:

```text
main
```

## Step 8: Create Phase 7 Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-07-cicd-self-hosted/.github/workflows
mkdir -p deployment/phase-07-cicd-self-hosted/k8s
mkdir -p .github/workflows
```

Why this step exists:

The deployment folder stores teaching copies of the files. The root `.github/workflows` folder is where GitHub Actions actually reads workflows.

## Step 9: Add GitHub Actions Secrets And Variables

In GitHub, go to:

```text
Repository
Settings
Secrets and variables
Actions
```

Create this variable (under the Variables tab):

| Type | Name | Value |
| --- | --- | --- |
| Variable | `PHASE7_PUBLIC_APP_URL` | `http://YOUR_EC2_PUBLIC_IP` |

Create this secret (under the Secrets tab):

| Type | Name | Value |
| --- | --- | --- |
| Secret | `PHASE7_DB_PASSWORD` | Strong PostgreSQL password |

Why this step exists:

The deploy workflow creates the Kubernetes Secret from the GitHub secret value and sets the CORS origin from the variable. The password must never be committed into YAML in the repository. The difference between the two types: a Variable is visible in plain text in the repository settings and in workflow logs, which is fine for a public URL. A Secret is encrypted, never shown again after saving, and automatically masked in workflow logs.

Reference:

- GitHub Actions secrets: https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions
- GitHub Actions variables: https://docs.github.com/en/actions/learn-github-actions/variables

## Step 10: Install GitHub Actions Self-Hosted Runner

In GitHub, go to:

```text
Repository
Settings
Actions
Runners
New self-hosted runner
Linux
x64
```

GitHub will show download and configure commands generated for your repository, including a registration token. Run those commands on the EC2 server exactly as shown. They look similar to this (do not copy this block, use the one GitHub shows you because the token is unique):

```text
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-X.Y.Z.tar.gz -L https://github.com/actions/runner/releases/download/...
tar xzf ./actions-runner-linux-x64-X.Y.Z.tar.gz
./config.sh --url https://github.com/ashraful2430/N-tier-application --token XXXXXXXX
```

During `./config.sh`, accept the defaults. The default labels include `self-hosted`, which is the label the deploy workflow targets.

After configuration, start the runner:

```bash
cd ~/actions-runner
./run.sh
```

For a student lab, keep this terminal open while testing. The runner shows `Listening for Jobs` when ready, and prints each job as it runs.

Why this step exists:

The deploy workflow must run on the EC2 server because that server owns the local Kind cluster. GitHub-hosted runners are fresh disposable VMs in GitHub's cloud; they cannot reach a Kind cluster living on your EC2 machine.

Security note:

Self-hosted runners can execute workflow commands on your server. Only use them with repositories and workflows you trust. Never attach a self-hosted runner to a public repository that accepts pull requests from strangers, because a malicious pull request could run code on your server.

Reference:

- Self-hosted runners: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners

## Step 11: Create Root `.dockerignore`

Run:

```bash
cd /opt/devops-launchboard/app-source
vim .dockerignore
```

Paste:

```dockerignore
.git
.github
.venv
backend/.venv
frontend/node_modules
frontend/dist
node_modules
__pycache__
**/__pycache__
*.pyc
.pytest_cache
.ruff_cache
.env
.env.*
deployment/phase-04-docker-compose/.env
```

Line explanation:

- `.git` keeps Git history out of Docker builds.
- `.github` keeps GitHub Actions workflow files out of images — they have no reason to be inside a container, and this repository's own pipeline files live there.
- `.venv` and `backend/.venv` keep local Python virtual environments out of images; the Dockerfile creates its own inside the build.
- `frontend/node_modules` keeps local frontend dependencies out of images; the Dockerfile's builder stage runs its own `npm install`/`npm ci`.
- `frontend/dist` ignores any old local build output so a stale build never accidentally gets copied in.
- `node_modules` ignores any root-level Node dependencies outside the `frontend/` folder.
- `__pycache__`, `**/__pycache__`, and `*.pyc` ignore Python bytecode caches.
- `.pytest_cache` and `.ruff_cache` ignore test and lint caches.
- `.env` and `.env.*` keep real secret env files out of images — only `.env.example` style placeholder files should ever reach a build context.
- `deployment/phase-04-docker-compose/.env` ignores the real env file from the Phase 4 lab, in case a student worked through phases in order on the same checkout.

Why this file exists:

Docker should not copy secrets, local virtual environments, dependency folders, caches, or build output into images. In CI this also matters for speed: a smaller build context uploads to the Docker daemon faster on every single pipeline run.

Reference:

- Docker build context: https://docs.docker.com/build/concepts/context/

## Step 12: Create Kind Config, Dockerfiles, And Nginx Config

The original guide referenced these files without showing their content. Here is every file in full. They mirror the Phase 6 files with three differences: the Kind cluster is named `launchboard-cicd`, the Dockerfile paths point to `deployment/phase-07-cicd-self-hosted/`, and the image tags are set by the CI pipeline using the Git commit SHA.

### kind-config.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/kind-config.yaml
```

Paste:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: launchboard-cicd
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: ingress-ready=true
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
```

Line explanation:

- `kind: Cluster` tells Kind that this YAML file describes a cluster.
- `apiVersion: kind.x-k8s.io/v1alpha4` is the current stable schema version for Kind cluster configs.
- `name: launchboard-cicd` names the cluster. The deploy workflow uses this name to check whether the cluster already exists, so it only creates it on the first run and reuses it on every run after that.
- `role: control-plane` creates one node running the full Kubernetes control plane. One node is enough for a CI deployment target.
- `node-labels: ingress-ready=true` adds the label that the official Kind Ingress Nginx manifest looks for with a `nodeSelector`. Without this label the Ingress Controller Pod cannot schedule.
- `extraPortMappings` forwards port 80 and 443 from the EC2 host into the Kind node container. This is how public browser traffic reaches the cluster.

Reference:

- Kind cluster configuration: https://kind.sigs.k8s.io/docs/user/configuration/
- Kind ingress setup: https://kind.sigs.k8s.io/docs/user/ingress/

### Dockerfile.backend

```bash
vim deployment/phase-07-cicd-self-hosted/Dockerfile.backend
```

Paste:

```dockerfile
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app

RUN python -m venv /opt/venv

COPY backend/pyproject.toml backend/alembic.ini ./
COPY backend/app ./app
COPY backend/alembic ./alembic

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir ".[dev]"

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_ENV=production

RUN groupadd --system --gid 10001 app \
    && useradd --system \
       --uid 10001 \
       --gid 10001 \
       --home-dir /app \
       --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

RUN chown -R app:app /app /opt/venv

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

Line explanation:

- `FROM python:3.12-slim AS builder` starts the first stage of a multi-stage build. `AS builder` names this stage so the second stage can copy files from it; the builder stage itself is not included in the final image.
- `ENV PYTHONDONTWRITEBYTECODE=1` stops Python writing `.pyc` cache files to disk, keeping the image clean.
- `ENV PYTHONUNBUFFERED=1` forces Python to write output directly to stdout so logs appear in real time in `kubectl logs` and in GitHub Actions logs.
- `ENV VIRTUAL_ENV=/opt/venv` and `ENV PATH="/opt/venv/bin:${PATH}"` create and prioritize a virtual environment at a known path so it can be copied between stages and so `python`, `uvicorn`, and `alembic` resolve to the venv versions.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency definitions before source code. This is a Docker layer-caching trick that matters in CI: if dependencies have not changed between commits, the pipeline reuses the cached install layer and the build finishes much faster.
- `RUN pip install --no-cache-dir ".[dev]"` installs the app together with the dev extras group (`ruff`, `pytest`, `pytest-asyncio`, `httpx`). Alembic itself is a base dependency, not a dev extra, so it would be installed either way; the dev extras are along for the ride here. `--no-cache-dir` keeps the layer small.
- `FROM python:3.12-slim AS runtime` starts a fresh final stage containing only what is explicitly copied: the venv and the app code. No pip cache, no build leftovers.
- `groupadd --system app` and `useradd --system ... app` create a non-login service user so the container does not run as root.
- `HEALTHCHECK` polls `/health` so Docker itself can report container health.
- `CMD [...]` starts Uvicorn in the foreground. `--proxy-headers` makes FastAPI trust the `X-Forwarded-*` headers added by the Nginx layers in front of it.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/

### Dockerfile.frontend

```bash
vim deployment/phase-07-cicd-self-hosted/Dockerfile.frontend
```

Paste:

```dockerfile
FROM node:22-alpine AS builder

WORKDIR /app

ARG VITE_API_URL=""
ENV VITE_API_URL=${VITE_API_URL}

COPY frontend/package*.json ./
RUN npm ci

COPY frontend/ ./
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

COPY deployment/phase-07-cicd-self-hosted/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a minimal Node.js 22 image only for compiling the React app. Node.js does not appear in the final image at all.
- `ARG VITE_API_URL=""` with `ENV VITE_API_URL=${VITE_API_URL}` lets the build embed an API base URL at build time. Left empty, the frontend uses relative `/api` paths, which is what you want here because Nginx proxies those paths.
- `COPY frontend/package*.json ./` followed by `RUN npm ci` is the same layer-caching pattern as the backend: unchanged lockfile means a cached, instant dependency install on the next CI run. `npm ci` installs exact versions from `package-lock.json` for reproducible builds.
- `RUN npm run build` produces static files in `/app/dist`.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine` is the official Nginx image designed to run as a non-root user on port 8080.
- `COPY deployment/phase-07-cicd-self-hosted/nginx-frontend.conf ...` installs the custom config from the Phase 7 folder. This is the one line that differs from Phase 6, which copied from the phase-6 folder.
- `COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html` copies the compiled app into the web root, owned by UID/GID 101, the nginx user in the unprivileged image.
- `CMD ["nginx", "-g", "daemon off;"]` keeps Nginx in the foreground so the container stays alive.

Reference:

- Vite environment variables: https://vite.dev/guide/env-and-mode
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged

### nginx-frontend.conf

```bash
vim deployment/phase-07-cicd-self-hosted/nginx-frontend.conf
```

Paste:

```nginx
server {
    listen 8080;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    client_max_body_size 10M;

    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok";
    }

    location /api/ {
        proxy_pass http://launchboard-backend:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /health {
        proxy_pass http://launchboard-backend:8000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /ready {
        proxy_pass http://launchboard-backend:8000/ready;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Line explanation:

- `listen 8080` because the unprivileged Nginx image cannot bind ports below 1024.
- `location = /healthz` answers `200 ok` instantly for the Kubernetes probes, with `access_log off` so probes do not flood the logs.
- `location /api/` with `proxy_pass http://launchboard-backend:8000/api/` forwards API calls to the backend Kubernetes Service by its DNS name. The trailing slashes on both sides keep the `/api/` prefix intact when forwarding.
- The `proxy_set_header` lines pass the original host, client IP, forwarding chain, and original scheme to the backend so logging and CORS logic see real client information.
- `location /` with `try_files $uri $uri/ /index.html` is the React Router fallback: direct navigation to a route like `/dashboard` falls back to `index.html` so the client-side router can render the page.

Reference:

- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- Nginx try_files: https://nginx.org/en/docs/http/ngx_http_core_module.html#try_files

## Step 13: Create Kubernetes Manifests

These are the deployment target the CI/CD workflow applies on every run. They mirror Phase 6 with one important difference: the backend and frontend image tags use the placeholder `IMAGE_TAG_PLACEHOLDER`, which the deploy workflow replaces with the Git commit SHA on every deployment. This is what makes rollouts and rollbacks tied to specific commits.

```bash
cd /opt/devops-launchboard/app-source
```

### namespace.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/namespace.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    app.kubernetes.io/name: devops-launchboard
    app.kubernetes.io/part-of: devops-launchboard
```

Line explanation:

- `kind: Namespace` with `name: devops-launchboard` creates the namespace that all other resources live in, isolating the app from everything else in the cluster.

### configmap.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/configmap.yaml
```

Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: launchboard-config
  namespace: devops-launchboard
data:
  APP_NAME: DevOps LaunchBoard API
  APP_ENV: production
  CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP
  SEED_DEMO_DATA: "true"
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
```

Line explanation:

- `CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP` is a placeholder. You can replace it before committing, but you do not have to: the deploy workflow patches this value from the GitHub Actions variable `PHASE7_PUBLIC_APP_URL` on every deployment. Keeping the real value in a GitHub variable means changing the EC2 IP never requires a code change.
- The remaining keys configure the app name, environment, demo data seeding, and database identity, identical to Phase 6.

Reference:

- Kubernetes ConfigMaps: https://kubernetes.io/docs/concepts/configuration/configmap/

### secret.example.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/secret.example.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: launchboard-secret
  namespace: devops-launchboard
type: Opaque
stringData:
  POSTGRES_PASSWORD: CHANGE_ME_STRONG_PASSWORD
  DATABASE_URL: postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard
```

This is a reference file only. The real Secret is created by the deploy workflow from the GitHub Actions secret `PHASE7_DB_PASSWORD`. Never commit real credentials.

Reference:

- Kubernetes Secrets: https://kubernetes.io/docs/concepts/configuration/secret/

### pvc.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/pvc.yaml
```

Paste:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: launchboard-postgres-pvc
  namespace: devops-launchboard
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Line explanation:

- `accessModes: ReadWriteOnce` allows one node to mount the volume for writing, correct for PostgreSQL.
- `storage: 5Gi` is served by Kind's built-in local-path provisioner, so database data survives Pod restarts (but not deletion of the Kind cluster itself).

Reference:

- PersistentVolumeClaims: https://kubernetes.io/docs/concepts/storage/persistent-volumes/#persistentvolumeclaims

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-postgres-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-db
  namespace: devops-launchboard
  labels:
    app: launchboard-db
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: launchboard-db
  template:
    metadata:
      labels:
        app: launchboard-db
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: postgres
              containerPort: 5432
          env:
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: launchboard-config
                  key: POSTGRES_DB
            - name: POSTGRES_USER
              valueFrom:
                configMapKeyRef:
                  name: launchboard-config
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: launchboard-secret
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - launchboard_user
                - -d
                - launchboard
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - launchboard_user
                - -d
                - launchboard
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: launchboard-postgres-pvc
```

Line explanation:

- `strategy.type: Recreate` stops the old Pod before starting a new one, required because the PVC is `ReadWriteOnce` and only one Pod may mount it.
- `env` pulls database identity from the ConfigMap and the password from the Secret that the workflow creates.
- `readinessProbe` and `livenessProbe` both run `pg_isready` so the migration Job and backend only see the database once it actually accepts connections.
- Resource limits are smaller than Phase 6 (500m CPU, 512Mi memory) because the whole stack shares one t3.small in this phase.

Reference:

- Deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Probes: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-postgres-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-db
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-db
  ports:
    - name: postgres
      port: 5432
      targetPort: 5432
```

Line explanation:

- `metadata.name: launchboard-db` is the DNS name used in `DATABASE_URL`. `type: ClusterIP` keeps the database reachable only from inside the cluster.

Reference:

- Services: https://kubernetes.io/docs/concepts/services-networking/service/

### launchboard-migration-job.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-migration-job.yaml
```

Paste:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: launchboard-migrate
  namespace: devops-launchboard
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app: launchboard-migrate
    spec:
      restartPolicy: OnFailure
      containers:
        - name: migrate
          image: launchboard-backend:IMAGE_TAG_PLACEHOLDER
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
                echo "waiting for postgres"
                sleep 2
              done
              alembic upgrade head
          envFrom:
            - configMapRef:
                name: launchboard-config
            - secretRef:
                name: launchboard-secret
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
```

Line explanation:

- `image: launchboard-backend:IMAGE_TAG_PLACEHOLDER` is replaced by the deploy workflow with the short Git commit SHA before applying, so migrations always run with the exact code being deployed.
- `imagePullPolicy: IfNotPresent` is essential here: the image only exists inside the Kind node (loaded with `kind load docker-image`), not on Docker Hub. If the policy were `Always`, Kubernetes would try to pull from a registry and fail.
- The `until` loop waits for PostgreSQL to accept TCP connections before running `alembic upgrade head`.
- Important CI detail: Kubernetes Jobs are immutable after creation. Re-applying a Job with a changed image fails with a `field is immutable` error. The deploy workflow handles this by deleting the old Job before every apply, so a fresh migration Job runs on every deployment.

Reference:

- Jobs: https://kubernetes.io/docs/concepts/workloads/controllers/job/

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-backend-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
  labels:
    app: launchboard-backend
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: launchboard-backend
  template:
    metadata:
      labels:
        app: launchboard-backend
    spec:
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: launchboard-backend:IMAGE_TAG_PLACEHOLDER
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
                echo "waiting for postgres"
                sleep 2
              done
              exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
          ports:
            - name: http
              containerPort: 8000
          envFrom:
            - configMapRef:
                name: launchboard-config
            - secretRef:
                name: launchboard-secret
          readinessProbe:
            httpGet:
              path: /ready
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 20
            periodSeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 400m
              memory: 384Mi
```

Line explanation:

- `image: launchboard-backend:IMAGE_TAG_PLACEHOLDER` is the rollback mechanism in disguise. Every deployment substitutes a unique commit SHA, so each deployment produces a new ReplicaSet referencing a specific image version. `kubectl rollout undo` then has a real previous version to go back to. If the tag never changed, rollback would point to the same image bytes and do nothing.
- `runAsUser: 10001` and `runAsGroup: 10001` are required because the Dockerfile uses `USER app`, a name, and the kubelet can only verify numeric UIDs against `runAsNonRoot: true`. Without them the Pods fail with `CreateContainerConfigError` (`image has non-numeric user (app), cannot verify user is non-root`). UID 10001 is pinned explicitly in the Dockerfile's `groupadd --gid 10001` / `useradd --uid 10001` instead of relying on whatever UID the system would otherwise auto-assign; confirm with `docker run --rm launchboard-backend:TAG id -u`.
- `maxUnavailable: 0` keeps full capacity during the rolling update; `maxSurge: 1` allows one extra Pod temporarily.
- `exec uvicorn ...` replaces the shell with Uvicorn so it receives termination signals directly, which makes graceful rollouts work.
- Resources are sized down slightly from Phase 6 to fit a single t3.small.

### launchboard-backend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-backend-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-backend
  ports:
    - name: http
      port: 8000
      targetPort: 8000
```

- `metadata.name: launchboard-backend` is the DNS name the frontend Nginx `proxy_pass` targets.

### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-frontend-deployment.yaml
```

Paste:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
  labels:
    app: launchboard-frontend
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: launchboard-frontend
  template:
    metadata:
      labels:
        app: launchboard-frontend
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        fsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: frontend
          image: launchboard-frontend:IMAGE_TAG_PLACEHOLDER
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 15
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
```

- `runAsUser: 101` matches the nginx user in the unprivileged image, same as Phase 6.
- `image: launchboard-frontend:IMAGE_TAG_PLACEHOLDER` follows the same SHA substitution pattern as the backend.

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/launchboard-frontend-service.yaml
```

Paste:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: launchboard-frontend
  namespace: devops-launchboard
spec:
  type: ClusterIP
  selector:
    app: launchboard-frontend
  ports:
    - name: http
      port: 80
      targetPort: 8080
```

- `port: 80` is what the Ingress targets; `targetPort: 8080` is where Nginx listens in the Pod.

### ingress.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/ingress.yaml
```

Paste:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: launchboard-ingress
  namespace: devops-launchboard
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: launchboard-frontend
                port:
                  number: 80
```

- All traffic entering port 80 on the EC2 host flows through the Kind port mapping into the Ingress Controller, which routes everything to the frontend Service. The frontend's Nginx then proxies `/api`, `/health`, and `/ready` to the backend.

### hpa.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/hpa.yaml
```

Paste:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: launchboard-backend-hpa
  namespace: devops-launchboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: launchboard-backend
  minReplicas: 2
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

- Same HPA pattern as Phase 6 with `maxReplicas: 4` to respect the smaller instance.
- HPA needs CPU metrics to exist. The deploy workflow installs Metrics Server into the Kind cluster (with the `--kubelet-insecure-tls` flag that Kind requires) on the first run. Without Metrics Server, `kubectl get hpa` would show `<unknown>` targets forever.

### kustomization.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/kustomization.yaml
```

Paste:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - pvc.yaml
  - launchboard-postgres-deployment.yaml
  - launchboard-postgres-service.yaml
  - launchboard-migration-job.yaml
  - launchboard-backend-deployment.yaml
  - launchboard-backend-service.yaml
  - launchboard-frontend-deployment.yaml
  - launchboard-frontend-service.yaml
  - ingress.yaml
  - hpa.yaml
```

- `secret.example.yaml` is intentionally excluded; the workflow creates the real Secret from the GitHub Actions secret value.

Reference:

- Kustomize: https://kustomize.io/

## Step 14: Create `build-and-test.yml`

Create the real workflow first:

```bash
vim .github/workflows/build-and-test.yml
```

Paste:

```yaml
name: phase-7-build-and-test

on:
  workflow_dispatch:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  backend:
    name: Backend checks
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip

      - name: Install backend dependencies
        working-directory: backend
        run: |
          python -m pip install --upgrade pip
          pip install -e ".[dev]"

      - name: Run backend lint
        working-directory: backend
        run: ruff check .

      - name: Run backend smoke test
        working-directory: backend
        run: python -c "from app.main import app; print(app.title)"

      - name: Run backend tests when present
        working-directory: backend
        run: |
          if [ -d tests ]; then
            pytest
          else
            echo "No backend tests directory yet."
          fi

  frontend:
    name: Frontend checks
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: npm
          cache-dependency-path: frontend/package-lock.json

      - name: Install frontend dependencies
        working-directory: frontend
        run: npm ci

      - name: Run frontend lint
        working-directory: frontend
        run: npm run lint

      - name: Build frontend
        working-directory: frontend
        run: npm run build
```

Copy it to the teaching folder:

```bash
cp .github/workflows/build-and-test.yml deployment/phase-07-cicd-self-hosted/.github/workflows/build-and-test.yml
```

Line explanation:

- `name: phase-7-build-and-test` is the workflow name shown in the GitHub Actions tab.
- `on:` defines the triggers. `workflow_dispatch` adds a manual Run workflow button. `pull_request: branches: [main]` runs the checks on every pull request targeting main, so broken code is caught before merge. `push: branches: [main]` runs them again on every push to main.
- `permissions: contents: read` restricts the automatic `GITHUB_TOKEN` to read-only repository access. This workflow only reads code, so it should not hold write permissions. Least privilege applies to CI tokens too.
- `runs-on: ubuntu-latest` uses a GitHub-hosted runner. Lint and build checks do not need your EC2 server, and GitHub-hosted runners are free for public repositories, with a generous monthly free quota for private ones.
- The `backend` and `frontend` jobs have no `needs:` relationship, so they run in parallel, halving the feedback time.
- `actions/checkout@v4` clones the repository into the runner. Every job starts on a fresh machine, so every job must check out the code itself.
- `actions/setup-python@v5` with `cache: pip` installs Python 3.12 and caches downloaded packages between runs, keyed on the dependency files. The second run of this workflow installs dependencies in seconds instead of minutes.
- `working-directory: backend` makes each `run:` command execute inside the `backend/` folder, the same as typing `cd backend` first.
- `pip install -e ".[dev]"` installs the app in editable mode with dev extras, which include `ruff` and `pytest`.
- `ruff check .` is the lint gate. If any Python file violates the lint rules, this step exits non-zero and the workflow fails, blocking the pipeline.
- The smoke test `python -c "from app.main import app; print(app.title)"` proves the FastAPI application can at least be imported. Import errors (missing dependency, syntax error) fail here in seconds instead of failing later inside a container at deploy time.
- The conditional pytest block runs the test suite if a `tests` folder exists, and prints a friendly message instead of failing if it does not. This lets the pipeline work before any tests are written and automatically start enforcing tests the moment the folder appears.
- `actions/setup-node@v4` with `cache: npm` and `cache-dependency-path: frontend/package-lock.json` installs Node.js 22 and caches the npm download cache keyed on the lockfile.
- `npm ci` performs a clean, reproducible install from the lockfile.
- `npm run lint` fails the workflow on frontend lint errors.
- `npm run build` proves the production bundle compiles. A TypeScript error or broken import fails here, before any Docker image is ever built.

Why this workflow exists:

It is the quality gate. The deploy workflow should never be reached by code that cannot lint, import, or compile. Failing fast on a free GitHub-hosted runner costs nothing; failing late on your EC2 deployment target costs a broken environment.

Reference:

- Workflow syntax: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions
- setup-python: https://github.com/actions/setup-python
- setup-node: https://github.com/actions/setup-node

## Step 15: Create `docker-build-push.yml`

This workflow builds both Docker images, scans them with Trivy for known vulnerabilities, and pushes them to GitHub Container Registry (GHCR) when running on the main branch. GHCR is free for public repositories, so no Docker Hub account or paid registry is needed.

Create the real workflow:

```bash
vim .github/workflows/docker-build-push.yml
```

Paste:

```yaml
name: phase-7-docker-build-scan-push

on:
  workflow_dispatch:
  push:
    branches:
      - main

permissions:
  contents: read
  packages: write

jobs:
  build-scan-push:
    name: Build, scan, push ${{ matrix.component }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - component: backend
            dockerfile: deployment/phase-07-cicd-self-hosted/Dockerfile.backend
          - component: frontend
            dockerfile: deployment/phase-07-cicd-self-hosted/Dockerfile.frontend
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set image name
        run: |
          OWNER_LOWERCASE=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')
          echo "IMAGE_NAME=ghcr.io/${OWNER_LOWERCASE}/launchboard-${{ matrix.component }}" >> "$GITHUB_ENV"
          echo "IMAGE_TAG=${GITHUB_SHA::7}" >> "$GITHUB_ENV"

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build image
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ${{ matrix.dockerfile }}
          load: true
          push: false
          tags: |
            ${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}
            ${{ env.IMAGE_NAME }}:latest

      - name: Scan image with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}
          format: table
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: "0"

      - name: Log in to GitHub Container Registry
        if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push image
        if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
        run: |
          docker push ${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}
          docker push ${{ env.IMAGE_NAME }}:latest
```

Copy it to the teaching folder:

```bash
cp .github/workflows/docker-build-push.yml deployment/phase-07-cicd-self-hosted/.github/workflows/docker-build-push.yml
```

Line explanation:

- `permissions: packages: write` grants the automatic `GITHUB_TOKEN` permission to push images to GHCR. `contents: read` allows checking out the code. Nothing else is granted.
- `strategy.matrix` runs the same job twice in parallel, once with `component: backend` and once with `component: frontend`, each with its own Dockerfile path. One job definition, two images, half the wall-clock time.
- `fail-fast: false` means if the backend scan fails, the frontend job still finishes, so you see the full picture in one run instead of fixing problems one at a time.
- The `Set image name` step builds two environment variables used by later steps. `tr '[:upper:]' '[:lower:]'` lowercases the repository owner because GHCR requires lowercase image names, and GitHub usernames may contain capitals. `${GITHUB_SHA::7}` takes the first 7 characters of the commit SHA, the same short form `git log --oneline` shows. Writing `KEY=value` lines into the `$GITHUB_ENV` file is how one step exports variables to all later steps in the same job.
- `docker/setup-buildx-action@v3` enables BuildKit's extended builder, which is faster and supports better caching than the legacy builder.
- `docker/build-push-action@v6` performs the build. `context: .` uses the repository root as build context, which the Dockerfiles need because they copy from `backend/`, `frontend/`, and `deployment/`. `load: true` with `push: false` loads the built image into the local Docker daemon instead of pushing it, because the image must be scanned before it is allowed anywhere near a registry. Two `tags` are applied: the immutable commit SHA tag for traceability, and `latest` for convenience.
- `aquasecurity/trivy-action@master` scans the freshly built image against vulnerability databases. Using `@master` always pulls the latest version of the Trivy action. You can pin to a specific release tag (check https://github.com/aquasecurity/trivy-action/releases for available versions) for reproducibility in production, but `@master` is simplest for a lab. `severity: CRITICAL,HIGH` limits findings to the two most serious levels. `ignore-unfixed: true` skips vulnerabilities that have no released fix yet, since failing the build over something nobody can fix only teaches students to ignore the scanner. `exit-code: "0"` makes the scan informational: it prints the full vulnerability table in the workflow log but does not fail the build. This is the right setting for a student lab because most findings are in upstream base image OS packages (openssl, musl, zlib) that students cannot fix — only the base image maintainers can. In production, change this to `"1"` to block images with fixable CRITICAL or HIGH vulnerabilities from reaching the registry.
- The `if: github.ref == 'refs/heads/main' ...` conditions on the login and push steps make pushing happen only for the main branch. Builds from other refs are built and scanned but never published.
- `docker/login-action@v3` authenticates to `ghcr.io` using `github.actor` (the user who triggered the run) and the automatic `GITHUB_TOKEN`. No personal access token or stored password is needed; the token is short-lived and scoped to this run.
- The final step pushes both tags to GHCR.

One-time GHCR note:

The first push creates the packages as private even in a public repository. To let anyone (or the Kind cluster, if you later choose to pull instead of load) pull them, go to your GitHub profile, then Packages, open each `launchboard-*` package, then Package settings, then change visibility to Public.

Why this workflow exists:

It produces the versioned, scanned artifacts of the pipeline. Even though the deploy workflow in this phase builds images directly on the EC2 runner for simplicity, publishing scanned images to a registry is the production habit: it means any machine, any cluster, and any teammate can pull the exact image that passed the gates.

Reference:

- Docker Buildx action: https://github.com/docker/setup-buildx-action
- Docker build-push action: https://github.com/docker/build-push-action
- Trivy action: https://github.com/aquasecurity/trivy-action
- Working with GHCR: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

## Step 16: Create `deploy-k8s.yml`

This is the heart of the phase. It runs on the self-hosted EC2 runner, creates or reuses the Kind cluster, installs the Ingress Controller and Metrics Server on first run, builds and loads images tagged with the commit SHA, creates the Secret from GitHub, applies the manifests, waits for everything, and verifies the live app with curl.

Create the real workflow:

```bash
vim .github/workflows/deploy-k8s.yml
```

Paste:

```yaml
name: phase-7-deploy-kind

on:
  workflow_dispatch:
  push:
    branches:
      - main

permissions:
  contents: read

concurrency:
  group: phase-7-deploy
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy to Kind on EC2
    runs-on: self-hosted
    env:
      KIND_CLUSTER: launchboard-cicd
      NAMESPACE: devops-launchboard
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set image tag from commit SHA
        run: echo "IMAGE_TAG=${GITHUB_SHA::7}" >> "$GITHUB_ENV"

      - name: Create Kind cluster if it does not exist
        run: |
          if ! kind get clusters | grep -q "^${KIND_CLUSTER}$"; then
            kind create cluster --name "${KIND_CLUSTER}" \
              --config deployment/phase-07-cicd-self-hosted/kind-config.yaml
          else
            echo "Cluster ${KIND_CLUSTER} already exists, reusing it."
          fi
          kubectl cluster-info --context "kind-${KIND_CLUSTER}"

      - name: Install Nginx Ingress Controller if missing
        run: |
          if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/kind/deploy.yaml
            sleep 10
          fi
          kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=180s

      - name: Install Metrics Server if missing
        run: |
          if ! kubectl -n kube-system get deployment metrics-server >/dev/null 2>&1; then
            kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
            kubectl patch deployment metrics-server -n kube-system --type='json' \
              -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
          fi

      - name: Build images
        run: |
          docker build -f deployment/phase-07-cicd-self-hosted/Dockerfile.backend \
            -t "launchboard-backend:${IMAGE_TAG}" .
          docker build -f deployment/phase-07-cicd-self-hosted/Dockerfile.frontend \
            -t "launchboard-frontend:${IMAGE_TAG}" .

      - name: Load images into Kind
        run: |
          kind load docker-image "launchboard-backend:${IMAGE_TAG}" --name "${KIND_CLUSTER}"
          kind load docker-image "launchboard-frontend:${IMAGE_TAG}" --name "${KIND_CLUSTER}"

      - name: Stamp image tag into manifests
        run: |
          sed -i "s|IMAGE_TAG_PLACEHOLDER|${IMAGE_TAG}|g" \
            deployment/phase-07-cicd-self-hosted/k8s/launchboard-backend-deployment.yaml \
            deployment/phase-07-cicd-self-hosted/k8s/launchboard-frontend-deployment.yaml \
            deployment/phase-07-cicd-self-hosted/k8s/launchboard-migration-job.yaml

      - name: Create namespace
        run: kubectl apply -f deployment/phase-07-cicd-self-hosted/k8s/namespace.yaml

      - name: Create or update application Secret
        run: |
          kubectl -n "${NAMESPACE}" create secret generic launchboard-secret \
            --from-literal=POSTGRES_PASSWORD='${{ secrets.PHASE7_DB_PASSWORD }}' \
            --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:${{ secrets.PHASE7_DB_PASSWORD }}@launchboard-db:5432/launchboard' \
            --dry-run=client -o yaml | kubectl apply -f -

      - name: Delete previous migration Job
        run: kubectl -n "${NAMESPACE}" delete job launchboard-migrate --ignore-not-found

      - name: Apply Kubernetes manifests
        run: kubectl apply -k deployment/phase-07-cicd-self-hosted/k8s

      - name: Set CORS origin from GitHub variable
        run: |
          kubectl -n "${NAMESPACE}" patch configmap launchboard-config --type merge \
            -p '{"data":{"CORS_ORIGINS":"${{ vars.PHASE7_PUBLIC_APP_URL }}"}}'
          kubectl -n "${NAMESPACE}" rollout restart deployment/launchboard-backend

      - name: Wait for database
        run: kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-db --timeout=180s

      - name: Wait for migration Job
        run: kubectl -n "${NAMESPACE}" wait --for=condition=complete job/launchboard-migrate --timeout=180s

      - name: Wait for application rollout
        run: |
          kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-backend --timeout=180s
          kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-frontend --timeout=180s

      - name: Verify application
        run: |
          sleep 5
          curl -fsS http://127.0.0.1/healthz
          curl -fsS http://127.0.0.1/health
          curl -fsS http://127.0.0.1/ready
          curl -fsS http://127.0.0.1/api/summary | head -c 400
          echo
          echo "Deployment of ${IMAGE_TAG} verified."
```

Copy it to the teaching folder:

```bash
cp .github/workflows/deploy-k8s.yml deployment/phase-07-cicd-self-hosted/.github/workflows/deploy-k8s.yml
```

Line explanation:

- `on: workflow_dispatch` plus `push: branches: [main]` means every merge to main deploys automatically, and you can also deploy manually with the Run workflow button.
- `concurrency: group: phase-7-deploy` with `cancel-in-progress: false` ensures only one deployment runs at a time. If two pushes land close together, the second waits for the first to finish instead of both fighting over the same cluster. This is a real production concern: overlapping deploys produce undefined cluster state.
- `runs-on: self-hosted` routes this job to your EC2 runner instead of GitHub's cloud, because only your EC2 machine has the Kind cluster.
- `env:` defines `KIND_CLUSTER` and `NAMESPACE` once at the job level so every step can use them without repetition.
- `echo "IMAGE_TAG=${GITHUB_SHA::7}" >> "$GITHUB_ENV"` derives a unique 7-character image tag from the commit being deployed and exports it to all later steps. This single line is what connects Git history to deployment history.
- The Kind creation step uses `kind get clusters | grep -q "^${KIND_CLUSTER}$"` to test for exact cluster name match. First run creates the cluster from `kind-config.yaml`; every later run reuses it, which keeps deploys fast and preserves the PostgreSQL data in the PVC between deployments.
- The Ingress install step checks for the `ingress-nginx` namespace before applying so the install only happens once, then always waits for the controller Pod to be ready. The manifest used is the Kind-specific provider variant pinned to controller v1.10.1, the same controller family used in Phase 6. Pinning the version means the pipeline does not silently change behavior when upstream releases something new.
- The Metrics Server step exists for the HPA. It is guarded by an existence check for a subtle reason: the `--kubelet-insecure-tls` JSON patch uses the `add` operation, which appends the argument again on every execution. Running it once behind a guard keeps it correct. The flag itself is required because Kind's kubelets use self-signed certificates, identical to the kubeadm situation in Phase 6 Scenario 7.
- The build step runs plain `docker build` for each image with the SHA tag. The build happens on the EC2 runner so the resulting image bytes are already on the machine that needs them.
- `kind load docker-image` copies the images from the host Docker daemon into the Kind node's internal container runtime. Kind clusters do not share the host's images; without this step every Pod would fail with `ImagePullBackOff` because the images exist nowhere a kubelet can pull from.
- The sed step replaces `IMAGE_TAG_PLACEHOLDER` with the real SHA in the three manifests that reference app images. The edit happens in the runner's checkout workspace, never in Git, and every run starts from a fresh checkout so the placeholder is always present to replace. After this step, the manifests describe exactly the images just built.
- The Secret step pipes `kubectl create secret --dry-run=client -o yaml` into `kubectl apply`. Plain `create` fails on the second run because the Secret already exists; plain `apply` of a YAML file would require committing the password. The dry-run pipe is the standard idempotent pattern: it generates the Secret YAML in memory from the GitHub secret and applies it, creating or updating as needed. GitHub automatically masks the secret value if it ever appears in logs.
- Deleting the migration Job before apply solves the Job immutability problem: Kubernetes refuses to modify a completed Job's image, so re-applying the kustomization on the second deploy would fail with `field is immutable`. Deleting first (with `--ignore-not-found` so the first run does not fail) means every deployment runs a fresh migration with the new image. `alembic upgrade head` is safe to re-run; it applies only migrations not yet applied.
- `kubectl apply -k` applies the whole kustomization. Because the image tags changed to a new SHA, Kubernetes starts a rolling update of backend and frontend automatically.
- The CORS patch step merges the real public URL from the GitHub variable into the ConfigMap after apply (apply resets it to the placeholder each time), then restarts the backend so its Pods re-read the environment. ConfigMap values consumed through `envFrom` are only read at Pod start, so a restart is required for the patch to take effect.
- The three wait steps gate the pipeline on reality: the database must be rolled out, the migration must complete, and both app Deployments must finish their rolling updates. `rollout status` exits non-zero on timeout, failing the workflow loudly instead of reporting a green check on a broken deploy.
- The verify step curls the app through the full public path: host port 80, into Kind, through the Ingress Controller, through the frontend Nginx, to the backend. `curl -fsS` fails the step on any non-2xx response. This is a smoke test of the same path a real user's browser takes.

Why this workflow exists:

This is continuous deployment: a push to main becomes a verified, running version of the app with no human typing kubectl commands. Every concept from Phase 6 (manifests, rollouts, probes, Ingress) is now driven by automation, and every deployed version is traceable to a commit SHA.

Reference:

- Self-hosted runners in workflows: https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/using-self-hosted-runners-in-a-workflow
- Concurrency: https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#concurrency
- kubectl rollout: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/
- Kind loading images: https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster

## Step 17: Create `rollback.yml`

Create the real workflow:

```bash
vim .github/workflows/rollback.yml
```

Paste:

```yaml
name: phase-7-rollback-kind

on:
  workflow_dispatch:
    inputs:
      deployment:
        description: Deployment to rollback
        required: true
        default: launchboard-backend
        type: choice
        options:
          - launchboard-backend
          - launchboard-frontend

permissions:
  contents: read

env:
  NAMESPACE: devops-launchboard

jobs:
  rollback:
    name: Rollback Kubernetes deployment
    runs-on: self-hosted
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Show rollout history
        run: kubectl -n "${NAMESPACE}" rollout history deployment/${{ github.event.inputs.deployment }}

      - name: Rollback deployment
        run: kubectl -n "${NAMESPACE}" rollout undo deployment/${{ github.event.inputs.deployment }}

      - name: Wait for rollback
        run: kubectl -n "${NAMESPACE}" rollout status deployment/${{ github.event.inputs.deployment }} --timeout=180s

      - name: Verify application
        run: |
          curl -fsS http://127.0.0.1/health
          curl -fsS http://127.0.0.1/ready
          curl -fsS http://127.0.0.1/api/summary
```

Copy it to the teaching folder:

```bash
cp .github/workflows/rollback.yml deployment/phase-07-cicd-self-hosted/.github/workflows/rollback.yml
```

Line explanation:

- `on: workflow_dispatch` with an `inputs` block makes this a manual-only workflow with a dropdown. `default: launchboard-backend` pre-selects an option, and `type: choice` with two `options` renders a select menu in the GitHub UI, so the operator picks backend or frontend instead of typing a name that could contain a typo.
- `runs-on: self-hosted` because only the EC2 runner can reach the Kind cluster.
- `Checkout repository` is included even though this workflow doesn't read any source files, because `kubectl` commands below assume the runner's working directory is set up like a normal job checkout.
- `rollout history` prints the revision list first, so the workflow log records what existed before the rollback. Each revision corresponds to a previous image SHA, which is exactly why the deploy workflow stamps unique SHA tags: without unique tags, every revision would point to the same image and `rollout undo` would change nothing.
- `rollout undo` switches the Deployment back to the previous ReplicaSet. The previous SHA-tagged image is still loaded inside the Kind node from its original deployment, so the old Pods start instantly without any pull.
- `rollout status` waits for the rollback to complete and fails the workflow on timeout.
- The final curl checks confirm the app actually works on the rolled-back version, because a rollback that completes but serves errors is not a successful rollback.

Note: there is no automatic rollback for the database. Alembic migrations applied by a newer version are still in the schema after rolling the backend back. For this app the migrations are additive so old code keeps working, but in real production, rolling back code that depends on a destructive migration requires a planned migration-down strategy.

Reference:

- kubectl rollout undo: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/kubectl_rollout_undo/
- workflow_dispatch inputs: https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#workflow_dispatch

## Step 18: Optional - Jenkinsfile

The phase folder lists a `Jenkinsfile` so students can compare GitHub Actions with Jenkins, the most common self-hosted CI server. This is optional reading; nothing in this phase requires Jenkins to be installed.

```bash
vim deployment/phase-07-cicd-self-hosted/Jenkinsfile
```

Paste:

```groovy
pipeline {
    agent any

    environment {
        IMAGE_TAG = "${env.GIT_COMMIT.take(7)}"
        KIND_CLUSTER = 'launchboard-cicd'
        NAMESPACE = 'devops-launchboard'
    }

    stages {
        stage('Backend checks') {
            steps {
                dir('backend') {
                    sh 'pip install -e ".[dev]"'
                    sh 'ruff check .'
                    sh 'python -c "from app.main import app; print(app.title)"'
                }
            }
        }
        stage('Frontend checks') {
            steps {
                dir('frontend') {
                    sh 'npm ci'
                    sh 'npm run lint'
                    sh 'npm run build'
                }
            }
        }
        stage('Build images') {
            steps {
                sh 'docker build -f deployment/phase-07-cicd-self-hosted/Dockerfile.backend -t launchboard-backend:${IMAGE_TAG} .'
                sh 'docker build -f deployment/phase-07-cicd-self-hosted/Dockerfile.frontend -t launchboard-frontend:${IMAGE_TAG} .'
            }
        }
        stage('Deploy to Kind') {
            steps {
                sh 'kind load docker-image launchboard-backend:${IMAGE_TAG} --name ${KIND_CLUSTER}'
                sh 'kind load docker-image launchboard-frontend:${IMAGE_TAG} --name ${KIND_CLUSTER}'
                sh 'sed -i "s|IMAGE_TAG_PLACEHOLDER|${IMAGE_TAG}|g" deployment/phase-07-cicd-self-hosted/k8s/launchboard-backend-deployment.yaml deployment/phase-07-cicd-self-hosted/k8s/launchboard-frontend-deployment.yaml deployment/phase-07-cicd-self-hosted/k8s/launchboard-migration-job.yaml'
                sh 'kubectl -n ${NAMESPACE} delete job launchboard-migrate --ignore-not-found'
                sh 'kubectl apply -k deployment/phase-07-cicd-self-hosted/k8s'
                sh 'kubectl -n ${NAMESPACE} rollout status deployment/launchboard-backend --timeout=180s'
                sh 'kubectl -n ${NAMESPACE} rollout status deployment/launchboard-frontend --timeout=180s'
            }
        }
        stage('Verify') {
            steps {
                sh 'curl -fsS http://127.0.0.1/health'
            }
        }
    }
}
```

What to notice in the comparison:

- A Jenkins `pipeline { stages { stage { steps } } }` block maps directly to a GitHub Actions `jobs: steps:` structure. The concepts (checkout, environment variables, shell steps, gates) are identical; only the syntax differs.
- Jenkins runs on a server you operate (similar in spirit to a self-hosted runner), so the same security warning applies: the CI server can execute anything on its host.

Reference:

- Jenkins pipeline syntax: https://www.jenkins.io/doc/book/pipeline/syntax/

## Step 19: Commit And Push

Run from the EC2 clone (or your local development machine if you created the files there):

```bash
cd /opt/devops-launchboard/app-source
git status
git add .dockerignore .github/workflows deployment/phase-07-cicd-self-hosted
git commit -m "Add phase 7 CI/CD deployment"
git push origin main
```

Why this step exists:

GitHub Actions reads workflows only after they are committed and pushed to the repository. Note that this very push will also trigger `phase-7-build-and-test`, `phase-7-docker-build-scan-push`, and `phase-7-deploy-kind`, because all three trigger on pushes to main. Make sure the self-hosted runner is running (`cd ~/actions-runner && ./run.sh`) before pushing, or the deploy job will sit queued waiting for it.

## Step 20: Run The Workflows

The push in Step 19 already triggered everything. To run them manually at any time, go to:

```text
Actions
phase-7-build-and-test
Run workflow
```

Then run:

```text
phase-7-docker-build-scan-push
```

Then run:

```text
phase-7-deploy-kind
```

Expected:

```text
Backend checks pass.
Frontend checks pass.
Docker images build.
Trivy scan passes.
Self-hosted runner builds and loads SHA-tagged images.
Kind cluster created on first run, reused after.
Migration Job completes.
Kubernetes rollout completes.
Curl verification passes.
```

## Step 21: Verify From EC2

Run:

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get ingress
kubectl -n devops-launchboard get hpa
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Confirm the deployed image matches the latest commit:

```bash
kubectl -n devops-launchboard get deployment launchboard-backend \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
git log --oneline -1
```

The image tag and the commit short SHA should match. This is the traceability the whole pipeline is built around.

Open in your browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

## Step 22: Test The Full CI/CD Loop

Prove that a code change flows to production automatically. Make a visible change, for example edit the app name:

```bash
vim deployment/phase-07-cicd-self-hosted/k8s/configmap.yaml
```

Change:

```yaml
  APP_NAME: DevOps LaunchBoard API v2
```

Commit and push:

```bash
git add deployment/phase-07-cicd-self-hosted/k8s/configmap.yaml
git commit -m "test ci/cd loop"
git push origin main
```

Watch the Actions tab: the deploy workflow starts on its own, runs on your EC2 runner, and a few minutes later the change is live. No kubectl commands were typed. This is the entire point of the phase.

## Step 23: Rollback From GitHub Actions

In GitHub, run:

```text
Actions
phase-7-rollback-kind
Run workflow
```

Choose from the dropdown:

```text
launchboard-backend
```

or:

```text
launchboard-frontend
```

The workflow log shows the rollout history, performs the undo, prints the now-running image SHA, and verifies with curl.

Why this step exists:

Rollback is a required production habit. If a deployment breaks the app, you need a repeatable, one-click way to return to the previous version, and you need it to be tested before the day you actually need it.

## Logs And Debugging

GitHub Actions:

```text
Actions
Open failed workflow
Open failed job
Read the failed step logs
```

EC2 Kubernetes checks:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard logs job/launchboard-migrate
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

Runner checks:

```bash
cd ~/actions-runner
./run.sh
```

Docker checks:

```bash
docker images | grep launchboard
kind get clusters
kubectl get nodes
```

## Troubleshooting

### Problem 1: Workflow Does Not Start

Common causes:

```text
Workflow file is not in root .github/workflows.
Workflow was not pushed to GitHub.
GitHub Actions is disabled for the repository.
```

Remember: the copies in deployment/phase-07-cicd-self-hosted/.github/workflows are teaching copies. GitHub only reads the root .github/workflows folder.

### Problem 2: Deploy Job Waits For Runner Forever

Common causes:

```text
Self-hosted runner is not running.
Runner was registered to another repository.
Runner labels do not match self-hosted.
```

Fix:

```bash
cd ~/actions-runner
./run.sh
```

### Problem 3: Deploy Fails Because Secret Or Variable Is Missing

Check GitHub:

```text
Settings
Secrets and variables
Actions
```

Required:

```text
Secret:   PHASE7_DB_PASSWORD
Variable: PHASE7_PUBLIC_APP_URL
```

A missing variable shows up as an empty CORS_ORIGINS patch; a missing secret fails the create-secret step.

### Problem 4: ImagePullBackOff In Kubernetes

This means the kubelet inside Kind tried to pull an image that only exists on the host. Find the tag the Deployment wants, then load it:

```bash
kubectl -n devops-launchboard get deployment launchboard-backend \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
echo
kind load docker-image launchboard-backend:THE_TAG_FROM_ABOVE --name launchboard-cicd
kind load docker-image launchboard-frontend:THE_TAG_FROM_ABOVE --name launchboard-cicd
```

If the tag shows `IMAGE_TAG_PLACEHOLDER`, the manifests were applied manually without the workflow's sed step. Re-run the deploy workflow.

### Problem 5: Migration Job Fails With "field is immutable"

This happens when applying manifests manually while an old Job exists. The workflow deletes the Job before applying; do the same manually:

```bash
kubectl -n devops-launchboard delete job launchboard-migrate --ignore-not-found
kubectl apply -k deployment/phase-07-cicd-self-hosted/k8s
```

### Problem 6: Docker Permission Denied In Workflow Logs

The runner user is not in the docker group:

```bash
sudo usermod -aG docker ubuntu
```

Then restart the runner (CTRL+C, then `./run.sh`) so it picks up the new group.

### Problem 7: Trivy Scan Fails The Build

Read the table in the workflow log. Each finding lists the package, the installed version, and the fixed version. Usually the fix is to rebuild on a newer base image (for example, a newer `python:3.12-slim` digest already contains the patched OS packages). Re-run the workflow after the base images update, or bump the base image versions in the Dockerfiles.

### Problem 8: Backend Checks Fail With ruff F401 "imported but unused"

If `ruff check .` fails with errors like:

```text
F401 [*] `app.models.deployment.Deployment` imported but unused
  --> alembic/env.py:9:35
```

The imports in `alembic/env.py` look unused to ruff, but they are intentionally imported for their side effect: loading them registers the SQLAlchemy models with `Base.metadata` so Alembic can detect and generate migrations. Without these imports, `alembic revision --autogenerate` would produce empty migrations.

Fix by adding a `# noqa: F401` comment to the import line in `backend/alembic/env.py`:

```python
from app.models.deployment import Deployment, Service  # noqa: F401
```

`# noqa: F401` tells ruff "this import is intentional, do not flag it." This is the standard pattern for Alembic `env.py` files across the Python ecosystem.

## Cleanup

Delete Kubernetes app:

```bash
kubectl delete namespace devops-launchboard
```

Delete Kind cluster:

```bash
kind delete cluster --name launchboard-cicd
```

Stop runner:

```text
Press CTRL + C in the runner terminal.
```

Remove runner from GitHub:

```text
Repository
Settings
Actions
Runners
Remove runner
```

Optional: delete published GHCR packages:

```text
GitHub profile
Packages
launchboard-backend / launchboard-frontend
Package settings
Delete this package
```

AWS cleanup:

- Terminate the EC2 instance.
- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check AWS Billing.

## Production Checklist

```text
[ ] EC2 runner created
[ ] Docker installed and ubuntu user in docker group
[ ] kubectl installed
[ ] Kind installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned
[ ] Self-hosted runner registered and running
[ ] PHASE7_PUBLIC_APP_URL variable created
[ ] PHASE7_DB_PASSWORD secret created
[ ] Root .github/workflows files created
[ ] Teaching copies created in deployment/phase-07-cicd-self-hosted
[ ] Phase 7 Dockerfiles created
[ ] kind-config.yaml and nginx-frontend.conf created
[ ] Phase 7 Kubernetes manifests created with IMAGE_TAG_PLACEHOLDER
[ ] Build and test workflow passes
[ ] Docker build and scan workflow passes
[ ] Images pushed to GHCR from main
[ ] Deploy workflow runs on self-hosted runner
[ ] Kind cluster created on first run
[ ] Ingress Controller installed
[ ] Metrics Server installed and HPA shows real targets
[ ] SHA-tagged images loaded into Kind
[ ] Migration Job completed
[ ] Kubernetes rollout succeeds
[ ] Deployed image SHA matches latest commit
[ ] Public app URL works
[ ] Full CI/CD loop tested with a real commit
[ ] Rollback workflow tested
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| GitHub Actions | https://docs.github.com/en/actions |
| Workflow syntax | https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions |
| Events that trigger workflows | https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows |
| Self-hosted runners | https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners |
| GitHub Actions secrets | https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions |
| GitHub Actions variables | https://docs.github.com/en/actions/learn-github-actions/variables |
| GitHub Container Registry | https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry |
| Docker Buildx action | https://github.com/docker/setup-buildx-action |
| Docker build-push action | https://github.com/docker/build-push-action |
| Trivy action | https://github.com/aquasecurity/trivy-action |
| Trivy documentation | https://trivy.dev/ |
| Kubernetes deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| kubectl rollout | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/ |
| Kubernetes Jobs | https://kubernetes.io/docs/concepts/workloads/controllers/job/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Kind loading images | https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster |
| Metrics Server | https://github.com/kubernetes-sigs/metrics-server |
| Jenkins pipeline | https://www.jenkins.io/doc/book/pipeline/ |

## Optional: Other CI Tools And Targets

This phase folder also contains two optional, fully self-contained bonus guides that are not required to move on to Phase 8:

```text
deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/README.md
```

Builds the exact same CI/CD pipeline as this guide, but with a self-hosted Jenkins server installed from scratch instead of GitHub Actions — useful if your organization already standardizes on Jenkins, or if you want to compare the two CI systems hands-on.

```text
deployment/phase-07-cicd-self-hosted/phase-7-cicd-EKS/README.md
```

Builds a CI/CD pipeline with GitHub-hosted runners, Docker Hub, and Amazon EKS instead of a self-hosted runner and a local Kind cluster — a preview of the cloud target Phase 8 covers in depth.

Both guides start from a fresh server and do not require completing the main walkthrough above first.

## What To Do Next

Move to:

```text
Phase 8: EKS
```

Why:

Phase 7 teaches CI/CD against a local Kubernetes cluster. Phase 8 moves the Kubernetes platform to AWS EKS so students can learn managed Kubernetes, cloud networking, and cloud-native deployment. The pipeline structure stays the same; only the deployment target changes, which is exactly why images were published to a registry in this phase.
