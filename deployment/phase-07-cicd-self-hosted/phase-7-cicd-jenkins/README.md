# Phase 7: CI/CD Automation — Jenkins From Scratch

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server and a GitHub repository.

You do not need to complete any previous phase before using this guide. This guide does not reuse the main Phase 7 (GitHub Actions) server, cluster, or files — it builds its own Jenkins server, its own Kind cluster, and its own copies of every file, end to end.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker, kubectl, Kind, and Jenkins are not installed yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Build

This phase builds a self-hosted CI/CD pipeline using Jenkins instead of GitHub Actions:

- Installs Jenkins directly on an EC2 server (the most common way teams run a self-hosted CI server).
- Creates a Jenkins Pipeline job that checks out the repository, lints and smoke-tests the backend, lints and builds the frontend, builds Docker images tagged with the Git commit SHA, creates a local Kind Kubernetes cluster if one does not already exist, loads the images into it, and deploys the app.
- Tags every build with the Git commit SHA so rollback is real, not cosmetic — the same lesson taught in the main Phase 7 guide, now reproduced with Jenkins instead of GitHub Actions.
- Adds a second Jenkins Pipeline job for one-click rollback.
- Polls GitHub for new commits on a schedule, so pushing code triggers a new build automatically without exposing the server to the internet.

## CI/CD Architecture

```text
Developer pushes to GitHub main
  |
  v
Jenkins polls GitHub on a schedule (no inbound traffic needed)
  |
  v
Jenkins server (runs directly on your EC2 instance)
  |
  | 1. Checkout
  | 2. Backend lint + smoke test
  | 3. Frontend lint + build
  | 4. Docker build (commit SHA tag)
  | 5. Create Kind cluster + Nginx Ingress if missing
  | 6. Load images into Kind
  | 7. Apply Kubernetes manifests
  | 8. Wait for rollout
  | 9. Verify with curl
  |
  v
Local Kind Kubernetes cluster (on the same EC2 instance)
  |
  v
DevOps LaunchBoard app
```

## When To Use This Architecture

Use Jenkins instead of GitHub Actions when:

- Your organization already runs Jenkins and you need to fit into existing pipelines.
- You want a CI server that is not tied to any single Git host (GitHub, GitLab, Bitbucket all work the same way with Jenkins).
- You need Jenkins' large plugin ecosystem (artifact repositories, ticketing system integrations, notification channels) that a specific Git host's native CI may not offer.
- You want full control over the CI server's OS, patching schedule, and installed tooling.

Do not use this exact architecture when:

- You only need basic CI/CD and your code already lives on GitHub — GitHub Actions (the main Phase 7 guide) needs less infrastructure to operate and patch.
- You need a long-term production platform — this guide deploys to a local Kind cluster on a single EC2 instance, the same teaching-only target as the main Phase 7 guide.
- You cannot dedicate a server to running Jenkins continuously. Unlike GitHub-hosted runners, Jenkins itself is a process you must patch, back up, and keep running.

Production note:

Jenkins runs continuously on a server you fully control, so it carries the same risk as any self-hosted runner: anyone who can push a malicious Jenkinsfile to a repository Jenkins builds can run arbitrary commands on that server. For serious production use, run build agents on ephemeral, isolated nodes (Jenkins agents on Kubernetes or Docker), restrict which repositories and branches can trigger builds, and keep Jenkins itself patched and behind a reverse proxy with HTTPS.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-7-jenkins` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 40 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-7-jenkins-sg` |
| SSH Port | `22`, your IP only |
| Jenkins UI Port | `8080`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if testing HTTPS |

Do not open:

```text
8000
5432
6443
```

The backend, database, and Kubernetes API should not be public.

Why `t3.medium` instead of the `t3.small` used in the main Phase 7 guide: Jenkins itself is a persistent Java process that needs roughly 1-2 GB of heap memory on top of Docker, Kind, and the app's own Pods (PostgreSQL, backend, frontend, Nginx Ingress Controller). A `t3.small` (2 GB RAM total) runs out of memory once Jenkins and a running Kind cluster are both active; `t3.medium` (4 GB RAM) gives enough headroom.

## Files Included In This Phase

```text
deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
+-- kind-config.yaml
+-- Jenkinsfile                          (deploy pipeline)
+-- Jenkinsfile.rollback                 (rollback pipeline)
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
|   +-- kustomization.yaml
+-- README.md
```

## Step 1: Create EC2 Server

Run this step from AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-7-jenkins` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.medium` |
| Storage | 40 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| Custom TCP (Jenkins UI) | 8080 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere if testing HTTPS |

Why this step exists:

This single server runs Docker, Kind, kubectl, and Jenkins itself. Jenkins schedules and executes the pipeline directly on this machine, the same way a small company would run a first self-hosted Jenkins controller before splitting build agents onto separate machines.

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

These are the same baseline Linux tools every other phase installs: cloning the repository, editing files, downloading binaries, and reading JSON output.

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

Docker builds the backend and frontend images, and Kind itself runs Kubernetes nodes as Docker containers. Both the `ubuntu` user (for manual commands) and, later, the `jenkins` user (for pipeline runs) need to run Docker commands.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Install kubectl And Kind

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

`kind` creates the local Kubernetes cluster that the Jenkins pipeline deploys to, and `kubectl` is how both you and Jenkins talk to that cluster. Installing both to `/usr/local/bin` puts them on the PATH for every user on this machine, including the `jenkins` system user created in Step 7.

Reference:

- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
- Kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/

## Step 6: Create GitHub SSH Key And Clone The Repository

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-7-jenkins" -f ~/.ssh/devops_launchboard_github_key
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

Clone:

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

Why this step exists:

You need a local copy of the application source to create the Phase 7 Jenkins files and to build images. This key is only used by your own `ubuntu` user for this initial clone and manual edits; Jenkins gets its own separate deploy key in Step 11, which is a better security practice than sharing one key between a human user and an automated service.

## Step 7: Install Java And Jenkins

Jenkins is a Java application. Install a current LTS Java runtime first, then add Jenkins' own apt repository.

```bash
cd ~
sudo apt update
sudo apt install -y fontconfig openjdk-21-jre
java -version
```

Add the Jenkins repository and install:

```bash
sudo curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  -o /usr/share/keyrings/jenkins-keyring.asc

echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins
```

Start and enable Jenkins:

```bash
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins --no-pager
```

Expected: `active (running)`.

Why this step exists:

Jenkins is not a container or a managed service in this guide — it installs as a system service (`jenkins.service`) running under its own dedicated Linux user, also named `jenkins`. That user, not `ubuntu`, is who actually executes every pipeline stage, which is why later steps configure permissions specifically for the `jenkins` user.

Reference:

- Jenkins Debian/Ubuntu install: https://www.jenkins.io/doc/book/installing/linux/#debianubuntu

## Step 8: Open Jenkins And Finish The Setup Wizard

Get the initial administrator password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open in your browser:

```text
http://YOUR_EC2_PUBLIC_IP:8080
```

Paste the password from the command above into the "Unlock Jenkins" screen.

On the next screen, choose **Install suggested plugins**. This installs the Git plugin, Pipeline plugin, and other commonly needed plugins automatically; nothing further needs to be installed manually for this guide.

Create your first admin user when prompted (this replaces the temporary password going forward).

Confirm the Jenkins URL on the final screen matches `http://YOUR_EC2_PUBLIC_IP:8080/` and click **Start using Jenkins**.

Why this step exists:

The initial admin password file proves that whoever is unlocking Jenkins already has root access to the server it runs on — Jenkins will not let you create an account over the network without it. The suggested plugin set already includes everything this guide's Jenkinsfiles need (`git`, `workflow-aggregator` for Pipeline, `credentials-binding`); no extra plugin installation step is required.

## Step 9: Allow The Jenkins User To Run Docker And Kind

The `jenkins` system user (not `ubuntu`) executes every pipeline stage, so it needs the same Docker and kubeconfig access that you set up for `ubuntu` in Steps 4-5.

Add `jenkins` to the `docker` group:

```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Why `systemctl restart` is required: group membership is only read when a process starts. Jenkins was already running before this command, so its existing process is still in the old group list; restarting Jenkins starts it fresh with `docker` included.

Verify the `jenkins` user can reach Docker:

```bash
sudo -u jenkins docker ps
```

Expected: an empty container list (`CONTAINER ID   IMAGE   COMMAND ...` with no rows), not a permission error.

Why no kubeconfig step is needed yet: `kind create cluster` writes its kubeconfig to the home directory of whichever user runs it (`/var/lib/jenkins/.kube/config` for the `jenkins` user). Since the Jenkinsfile in Step 13 runs `kind create cluster` itself the first time it executes, the `jenkins` user's kubeconfig is created automatically on the first pipeline run — there is nothing to copy or chown manually.

## Step 10: Create Phase Folders And Root `.dockerignore`

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s
```

Create the root `.dockerignore` (shared by every Docker build in this repository, not specific to this phase):

```bash
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

Why this step exists:

Docker only reads `.dockerignore` from the build context root, and the build context in this phase is the repository root (every `docker build` command ends with a final `.`). Skipping this file would let Docker copy local virtual environments, `node_modules`, and cache folders into the build context, slowing builds and bloating images.

## Step 11: Create Dockerfiles And Nginx Config

### Dockerfile.backend

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.backend
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
    && pip install --no-cache-dir .

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

- `FROM python:3.12-slim AS builder` starts the first stage of a multi-stage build; the builder stage is not included in the final image.
- `ENV PYTHONDONTWRITEBYTECODE=1` and `ENV PYTHONUNBUFFERED=1` keep the image clean of `.pyc` files and make logs appear immediately.
- `ENV VIRTUAL_ENV=/opt/venv` and `ENV PATH="/opt/venv/bin:${PATH}"` create and prioritize a virtual environment at a known path so it can be copied between stages.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency definitions before source code, a Docker layer-caching trick: unchanged dependencies mean a cached, faster rebuild.
- `RUN pip install --no-cache-dir .` installs the application and its base dependencies. Alembic is a base dependency (not a dev-only extra), so this single install is enough for the migration Job too.
- `groupadd --system --gid 10001 app` / `useradd --system --uid 10001 --gid 10001 ...` create a non-login service user with an explicit, pinned numeric UID/GID rather than letting the system auto-assign one. A name-only `USER app` produces a non-numeric user that Kubernetes cannot verify against `runAsNonRoot`; pinning a fixed UID/GID keeps the Dockerfile and the Kubernetes `securityContext` (in Step 12) deterministic and in sync.
- `COPY --from=builder /opt/venv /opt/venv` and `COPY --from=builder /app /app` bring only the installed dependencies and app code into the clean runtime stage — no build tools, no pip cache.
- `RUN chown -R app:app /app /opt/venv` gives the non-root user ownership of its own files.
- `USER app` switches to the non-root user for the rest of the image.
- `HEALTHCHECK` polls `/health` every 30 seconds so Docker itself can report container health.
- `CMD [...]` starts Uvicorn listening on all interfaces. `--proxy-headers` makes FastAPI trust the `X-Forwarded-*` headers added by the Nginx Ingress in front of it.

### Dockerfile.frontend

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.frontend
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

COPY deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a minimal Node.js image only to compile the React app; Node.js does not appear in the final image.
- `ARG VITE_API_URL=""` with `ENV VITE_API_URL=${VITE_API_URL}` lets the build embed an API base URL at build time. Left empty, the frontend uses relative `/api` paths, which is what you want here because Nginx proxies those paths.
- `COPY frontend/package*.json ./` followed by `RUN npm ci` is the same layer-caching pattern as the backend, with `npm ci` installing exact versions from `package-lock.json` for reproducible builds.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine` is the official Nginx image designed to run as a non-root user on port 8080.
- `COPY deployment/.../nginx-frontend.conf ...` installs the custom config from this phase's own folder.
- `COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html` copies the compiled app into the web root, owned by UID/GID 101, the nginx user baked into the unprivileged image.
- `CMD ["nginx", "-g", "daemon off;"]` keeps Nginx in the foreground so the container stays alive.

### nginx-frontend.conf

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/nginx-frontend.conf
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

- `listen 8080` matches the unprivileged image's non-root port.
- `location = /healthz` returns a plain `200 ok` without hitting the backend — this is what the Kubernetes probes check.
- `location /api/`, `location = /health`, and `location = /ready` proxy those paths to `http://launchboard-backend:8000/...`, the backend's Kubernetes Service DNS name.
- `location / { try_files $uri $uri/ /index.html; }` falls back to `index.html` for any unmatched path, which is required for React Router to handle direct navigation to client-side routes.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged

## Step 12: Create The Kind Cluster Config

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/kind-config.yaml
```

Paste:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: launchboard-jenkins
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

- `name: launchboard-jenkins` names the Kind cluster. Using a name distinct from the main Phase 7 guide's `launchboard-cicd` cluster means both can coexist on the same machine if you have done both guides.
- `node-labels: ingress-ready=true` is a label the Nginx Ingress Controller's Kind-specific manifest looks for to decide which node to schedule onto.
- `extraPortMappings` maps the Kind container's ports 80 and 443 to the same ports on the EC2 host, so traffic to the EC2 instance's public IP on port 80 reaches the Ingress Controller running inside Kind.

This file is not applied directly with a `kind create cluster` command from you — the Jenkins pipeline in Step 13 creates the cluster itself, the first time it runs.

Reference:

- Kind configuration: https://kind.sigs.k8s.io/docs/user/configuration/

## Step 13: Create The Kubernetes Manifests

All manifests go inside `deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/`.

### namespace.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/namespace.yaml
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: devops-launchboard
  labels:
    app.kubernetes.io/name: devops-launchboard
    app.kubernetes.io/part-of: devops-launchboard
```

A Namespace is a logical boundary inside Kubernetes; every other resource below sets `namespace: devops-launchboard` to belong to it.

### configmap.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/configmap.yaml
```

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

This file is for reference only — the Jenkins pipeline actually creates this ConfigMap itself from the `PUBLIC_APP_URL` build parameter, so `CORS_ORIGINS` ends up correct without manual editing. `CORS_ORIGINS` tells the FastAPI backend which browser origin may call the API; if it does not match the URL in your browser's address bar, the browser blocks the API responses.

### secret.example.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/secret.example.yaml
```

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

Example only, same reasoning as `configmap.yaml` — the Jenkins pipeline creates the real Secret from the `DB_PASSWORD` build parameter. Never commit real credentials into this file.

### pvc.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/pvc.yaml
```

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

No `storageClassName` is set, so Kind's built-in `local-path` provisioner (the cluster's default StorageClass) creates the volume from the node's local disk. This is the same approach used in Phase 6's Kind scenario; it is fine for a single-node teaching cluster, but the data does not survive deleting the Kind cluster itself.

### launchboard-postgres-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-postgres-deployment.yaml
```

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

- `strategy.type: Recreate` terminates the existing Pod before creating a new one, required for a single-writer database that holds an exclusive lock on its volume.
- `image: postgres:16-alpine` is the official upstream image — Jenkins never builds this one, only the backend and frontend images.
- `env` reads `POSTGRES_DB`/`POSTGRES_USER` from the ConfigMap and `POSTGRES_PASSWORD` from the Secret, exactly what the official Postgres image's entrypoint needs to create the database on first start.
- `readinessProbe`/`livenessProbe` run `pg_isready` inside the container rather than an HTTP check, since PostgreSQL is not an HTTP service.

### launchboard-postgres-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-postgres-service.yaml
```

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

`launchboard-db` becomes the DNS name other Pods use to reach PostgreSQL; the `DATABASE_URL` in the Secret depends on this exact name. `ClusterIP` keeps the database unreachable from outside the cluster.

### launchboard-migration-job.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml
```

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

- `image: launchboard-backend:IMAGE_TAG_PLACEHOLDER` is a literal placeholder string, not a real tag. The Jenkins pipeline's "Stamp Image Tag Into Manifests" stage replaces `IMAGE_TAG_PLACEHOLDER` with the actual Git commit SHA before applying this file — explained fully in Step 14.
- A Job runs its Pod once to completion and stops, unlike a Deployment. `restartPolicy: OnFailure` retries only on failure, not after success.
- The `until python -c "import socket; ..."` loop blocks until PostgreSQL accepts TCP connections, preventing `alembic upgrade head` from running before the database is ready.

### launchboard-backend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml
```

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

- `image: launchboard-backend:IMAGE_TAG_PLACEHOLDER` gets stamped with the real commit SHA by Jenkins, exactly like the migration Job above. This is the rollback mechanism in disguise: every build produces a uniquely tagged image, so each deployment creates a new ReplicaSet referencing a specific version. `kubectl rollout undo` then has a real previous version to go back to — if the tag never changed, rollback would point at the same image bytes and do nothing.
- `runAsUser: 10001` and `runAsGroup: 10001` must match the `--uid 10001 --gid 10001` pinned in the Dockerfile, or the Pod fails with `CreateContainerConfigError` because the kubelet cannot verify a name-based `USER app` against `runAsNonRoot`.
- `rollingUpdate.maxSurge: 1` / `maxUnavailable: 0` updates Pods with zero downtime: Kubernetes never removes an old Pod until its replacement passes its readiness probe.
- `command` waits for PostgreSQL, then `exec`s into Uvicorn so it becomes PID 1 and receives termination signals directly, which is what makes rollouts and graceful shutdowns work correctly.

### launchboard-backend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-service.yaml
```

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

`launchboard-backend` becomes the DNS name the frontend's Nginx config proxies `/api`, `/health`, and `/ready` to.

### launchboard-frontend-deployment.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml
```

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

`runAsUser: 101` matches the nginx user baked into the `nginxinc/nginx-unprivileged` image, the same pattern as the backend's pinned UID 10001 but for a different base image with a different built-in user.

### launchboard-frontend-service.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-service.yaml
```

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

Port 80 is what the Ingress targets; port 8080 is the Pod's actual non-root port. The Service translates between the two.

### ingress.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/ingress.yaml
```

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

`ingressClassName: nginx` tells Kubernetes the Nginx Ingress Controller (installed automatically by the Jenkins pipeline in Step 14) should handle this resource. All traffic routes to the frontend Service; the frontend's own Nginx then proxies API paths to the backend.

### kustomization.yaml

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/kustomization.yaml
```

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
```

Lists every manifest so a single `kubectl apply -k` applies them all in order. `secret.example.yaml` is deliberately not listed — the Jenkins pipeline creates the real Secret separately with `kubectl create secret`, the same reasoning every other phase in this repository follows for credentials.

Reference:

- Kustomize documentation: https://kustomize.io/

## Step 14: Create The Jenkins Deploy Pipeline File

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile
```

Paste:

```groovy
pipeline {
  agent any

  parameters {
    string(name: 'PUBLIC_APP_URL', defaultValue: 'http://127.0.0.1', description: 'Public browser URL for CORS (your EC2 public IP, e.g. http://YOUR_EC2_PUBLIC_IP)')
    password(name: 'DB_PASSWORD', defaultValue: 'CHANGE_ME_STRONG_PASSWORD', description: 'PostgreSQL password for this lab')
  }

  environment {
    KIND_CLUSTER = 'launchboard-jenkins'
    NAMESPACE = 'devops-launchboard'
    PUBLIC_APP_URL = "${params.PUBLIC_APP_URL}"
    DB_PASSWORD = "${params.DB_PASSWORD}"
  }

  stages {
    stage('Backend Checks') {
      steps {
        dir('backend') {
          sh 'python3 -m venv .venv'
          sh '. .venv/bin/activate && python -m pip install --upgrade pip'
          sh '. .venv/bin/activate && pip install -e ".[dev]"'
          sh '. .venv/bin/activate && ruff check .'
          sh '. .venv/bin/activate && python -c "from app.main import app; print(app.title)"'
        }
      }
    }

    stage('Frontend Checks') {
      steps {
        dir('frontend') {
          sh 'npm ci'
          sh 'npm run lint'
          sh 'npm run build'
        }
      }
    }

    stage('Set Image Tag') {
      steps {
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
        }
        echo "Image tag for this build: ${env.IMAGE_TAG}"
      }
    }

    stage('Create Kind Cluster If Missing') {
      steps {
        sh '''
          if ! kind get clusters | grep -q "^${KIND_CLUSTER}$"; then
            kind create cluster --name "${KIND_CLUSTER}" \
              --config deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/kind-config.yaml
          else
            echo "Cluster ${KIND_CLUSTER} already exists, reusing it."
          fi
          kubectl cluster-info --context "kind-${KIND_CLUSTER}"
        '''
      }
    }

    stage('Install Nginx Ingress Controller If Missing') {
      steps {
        sh '''
          if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/kind/deploy.yaml
            sleep 10
          fi
          kubectl wait --namespace ingress-nginx \
            --for=condition=ready pod \
            --selector=app.kubernetes.io/component=controller \
            --timeout=180s
        '''
      }
    }

    stage('Build Images') {
      steps {
        sh '''
          docker build -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.backend \
            -t "launchboard-backend:${IMAGE_TAG}" .
          docker build -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Dockerfile.frontend \
            --build-arg VITE_API_URL= \
            -t "launchboard-frontend:${IMAGE_TAG}" .
        '''
      }
    }

    stage('Load Images Into Kind') {
      steps {
        sh '''
          kind load docker-image "launchboard-backend:${IMAGE_TAG}" --name "${KIND_CLUSTER}"
          kind load docker-image "launchboard-frontend:${IMAGE_TAG}" --name "${KIND_CLUSTER}"
        '''
      }
    }

    stage('Stamp Image Tag Into Manifests') {
      steps {
        sh '''
          sed -i "s|IMAGE_TAG_PLACEHOLDER|${IMAGE_TAG}|g" \
            deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml \
            deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml \
            deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml
        '''
      }
    }

    stage('Deploy To Kind') {
      steps {
        sh 'kubectl apply -f deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/namespace.yaml'
        sh '''
          kubectl create configmap launchboard-config \
            --namespace "${NAMESPACE}" \
            --from-literal=APP_NAME="DevOps LaunchBoard API" \
            --from-literal=APP_ENV=production \
            --from-literal=CORS_ORIGINS="${PUBLIC_APP_URL}" \
            --from-literal=SEED_DEMO_DATA=true \
            --from-literal=POSTGRES_DB=launchboard \
            --from-literal=POSTGRES_USER=launchboard_user \
            --dry-run=client -o yaml | kubectl apply -f -
        '''
        sh '''
          kubectl create secret generic launchboard-secret \
            --namespace "${NAMESPACE}" \
            --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
            --from-literal=DATABASE_URL="postgresql+asyncpg://launchboard_user:${DB_PASSWORD}@launchboard-db:5432/launchboard" \
            --dry-run=client -o yaml | kubectl apply -f -
        '''
        sh 'kubectl -n "${NAMESPACE}" delete job launchboard-migrate --ignore-not-found'
        sh 'kubectl apply -k deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s'
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-db --timeout=180s'
        sh 'kubectl -n "${NAMESPACE}" wait --for=condition=complete job/launchboard-migrate --timeout=180s'
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-backend --timeout=180s'
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/launchboard-frontend --timeout=180s'
      }
    }

    stage('Verify Application') {
      steps {
        sh '''
          sleep 5
          curl -fsS http://127.0.0.1/healthz
          curl -fsS http://127.0.0.1/health
          curl -fsS http://127.0.0.1/ready
          curl -fsS http://127.0.0.1/api/summary | head -c 400
          echo ""
          echo "Deployment of ${IMAGE_TAG} verified."
        '''
      }
    }
  }

  post {
    always {
      sh '''
        git checkout -- deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml \
          deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml \
          deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml || true
      '''
    }
  }
}
```

Line explanation:

- `pipeline { agent any }` is a declarative Jenkins Pipeline. `agent any` runs every stage directly on the Jenkins controller itself — appropriate here because Docker, Kind, and kubectl are all installed on this one EC2 instance and there are no separate build agents.
- `parameters { string(...) password(...) }` makes this a parameterized build: the Jenkins UI shows a form with these two fields before each run. `password(...)` masks the value in the UI and in logs, the same protection a GitHub Actions Secret gives you.
- `environment { ... }` defines variables available to every `sh` step as shell environment variables, including the two parameters re-exposed under names the shell scripts use directly.
- `stage('Backend Checks')` and `stage('Frontend Checks')` mirror the `build-and-test.yml` GitHub Actions workflow from the main Phase 7 guide: install dependencies, lint, smoke-test the backend's FastAPI app import, lint and build the frontend.
- `stage('Set Image Tag')` runs `git rev-parse --short=7 HEAD` to get the short commit SHA Jenkins just checked out, storing it in `env.IMAGE_TAG`. This is the exact same uniqueness mechanism the main Phase 7 GitHub Actions workflow uses (`${GITHUB_SHA::7}`), just read a different way because Jenkins does not provide a SHA environment variable by default the way GitHub Actions does.
- `stage('Create Kind Cluster If Missing')` and `stage('Install Nginx Ingress Controller If Missing')` are idempotent: they check whether the cluster/controller already exists before creating them, so re-running the pipeline never fails because "the cluster already exists." This means the very first pipeline run bootstraps the entire cluster from nothing, and every later run simply reuses it.
- `stage('Build Images')` and `stage('Load Images Into Kind')` build both images tagged with the commit SHA, then copy them into the Kind node's internal container runtime — Kind clusters do not share the host's Docker images, so without this step every Pod would fail with `ImagePullBackOff`.
- `stage('Stamp Image Tag Into Manifests')` replaces the literal string `IMAGE_TAG_PLACEHOLDER` in three YAML files with the real commit SHA using `sed -i`, directly in the Jenkins workspace's checked-out copy of those files, immediately before applying them.
- `stage('Deploy To Kind')` creates the namespace, creates or updates the ConfigMap and Secret from the build parameters (`--dry-run=client -o yaml | kubectl apply -f -` is the standard "create or update" idiom in kubectl, since plain `kubectl create` fails if the resource already exists), deletes any previous migration Job (Kubernetes Jobs are immutable, so a stale one must be deleted before applying a new one), applies the full kustomization, and waits for every rollout in dependency order.
- `stage('Verify Application')` curls the health, readiness, and summary endpoints through the Ingress on port 80, the same verification the main Phase 7 guide performs.
- `post { always { ... } }` runs after every build, success or failure. It restores the three manifest files back to their committed `IMAGE_TAG_PLACEHOLDER` state with `git checkout --`, undoing the `sed -i` from the stamp stage. Without this, the placeholder would be permanently replaced with a stale tag in the Jenkins workspace, and the *next* pipeline run's `sed` command would silently do nothing because the placeholder string would no longer exist.

Reference:

- Jenkins Pipeline syntax: https://www.jenkins.io/doc/book/pipeline/syntax/
- Jenkins declarative pipeline parameters: https://www.jenkins.io/doc/book/pipeline/syntax/#parameters

## Step 15: Create The Jenkins Rollback Pipeline File

```bash
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile.rollback
```

Paste:

```groovy
pipeline {
  agent any

  parameters {
    choice(name: 'DEPLOYMENT', choices: ['launchboard-backend', 'launchboard-frontend'], description: 'Which Deployment to roll back')
  }

  environment {
    NAMESPACE = 'devops-launchboard'
  }

  stages {
    stage('Show Rollout History') {
      steps {
        sh 'kubectl -n "${NAMESPACE}" rollout history deployment/${DEPLOYMENT}'
      }
    }

    stage('Roll Back To Previous Revision') {
      steps {
        sh 'kubectl -n "${NAMESPACE}" rollout undo deployment/${DEPLOYMENT}'
      }
    }

    stage('Wait For Rollback') {
      steps {
        sh 'kubectl -n "${NAMESPACE}" rollout status deployment/${DEPLOYMENT} --timeout=180s'
      }
    }

    stage('Show Running Image') {
      steps {
        sh '''
          kubectl -n "${NAMESPACE}" get deployment ${DEPLOYMENT} \
            -o jsonpath='{.spec.template.spec.containers[0].image}'
          echo ""
        '''
      }
    }

    stage('Verify Application') {
      steps {
        sh '''
          curl -fsS http://127.0.0.1/healthz
          curl -fsS http://127.0.0.1/health
          curl -fsS http://127.0.0.1/ready
          echo "Rollback of ${DEPLOYMENT} verified."
        '''
      }
    }
  }
}
```

Line explanation:

- `parameters { choice(...) }` renders a dropdown in the Jenkins UI with exactly two valid values, preventing a typo'd Deployment name from being passed to `kubectl`.
- `kubectl rollout undo` switches the Deployment back to its previous ReplicaSet. Because every build in the deploy pipeline tags images with a unique commit SHA, the previous ReplicaSet still references a real, different image — so this rollback actually changes what is running, not just touching the same bytes again.
- The image is still present inside the Kind node from when it was originally loaded, so the rolled-back Pods start instantly with no rebuild or re-pull.

Note: this file is a separate Pipeline job from the deploy pipeline (Step 17 covers creating that second job), so that rollback can run on demand without rebuilding or redeploying anything.

## Step 16: Commit And Push

```bash
cd /opt/devops-launchboard/app-source
git add .dockerignore deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins
git commit -m "Add Phase 7 Jenkins CI/CD from scratch"
git push origin main
```

Why this step exists:

The Jenkins jobs you create in the next step check out this exact path from your GitHub repository, so the Jenkinsfiles and supporting manifests must exist on `main` before Jenkins can run them.

## Step 17: Create A Jenkins-Specific GitHub Deploy Key

Jenkins needs its own way to clone the repository — reusing your personal SSH key from Step 6 would mix a human credential with an automated one, which is bad practice even in a lab.

```bash
cd ~
ssh-keygen -t ed25519 -C "jenkins-devops-launchboard" -f ~/jenkins_deploy_key -N ""
cat ~/jenkins_deploy_key.pub
```

Add the public key to GitHub:

```text
GitHub repository
Settings
Deploy keys
Add deploy key
Title: jenkins-devops-launchboard
Allow write access: unchecked
```

Read-only is enough: Jenkins only needs to check out code, never push to this repository.

In Jenkins, add the private key as a credential:

```text
Jenkins
Manage Jenkins
Credentials
System
Global credentials (unrestricted)
Add Credentials
Kind: SSH Username with private key
ID: github-jenkins-deploy-key
Username: git
Private Key: Enter directly -> paste the contents of ~/jenkins_deploy_key
```

Get the private key contents to paste:

```bash
cat ~/jenkins_deploy_key
```

Why this step exists:

When you configure the Pipeline job in the next step to check out from `git@github.com:ashraful2430/N-tier-application.git`, Jenkins needs a credential with permission to do that over SSH. This credential is scoped only to Jenkins and only allows reading this one repository.

Reference:

- Jenkins credentials: https://www.jenkins.io/doc/book/using/using-credentials/

## Step 18: Create The Jenkins Deploy Pipeline Job

In Jenkins:

```text
Dashboard
New Item
Name: launchboard-jenkins-deploy
Type: Pipeline
OK
```

Configure the job:

```text
Build Triggers:
  [x] Poll SCM
  Schedule: H/5 * * * *

Pipeline:
  Definition: Pipeline script from SCM
  SCM: Git
  Repository URL: git@github.com:ashraful2430/N-tier-application.git
  Credentials: github-jenkins-deploy-key
  Branch Specifier: */main
  Script Path: deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile
```

Click **Save**.

Why **Poll SCM** instead of a webhook: a GitHub webhook needs GitHub to reach Jenkins over the internet, which means opening port 8080 to the public — a real security tradeoff for a lab server. Poll SCM has Jenkins check GitHub for new commits on a schedule instead, which needs no inbound access at all. `H/5 * * * *` means "once every 5 minutes, at a random offset" (the `H` spreads load if many jobs share this schedule); Jenkins only actually starts a build if it finds a new commit since the last check.

Why this step exists:

This is the Jenkins equivalent of the main Phase 7 guide's `deploy-k8s.yml` GitHub Actions workflow: a build of this job runs every stage in the Jenkinsfile from Step 14, end to end, against this Kind cluster.

Reference:

- Jenkins Pipeline from SCM: https://www.jenkins.io/doc/book/pipeline/getting-started/#defining-a-pipeline-in-scm
- Jenkins Poll SCM cron syntax: https://www.jenkins.io/doc/book/pipeline/syntax/#cron-syntax

## Step 19: Run The Pipeline For The First Time

```text
Dashboard
launchboard-jenkins-deploy
Build with Parameters
PUBLIC_APP_URL: http://YOUR_EC2_PUBLIC_IP
DB_PASSWORD: choose a strong password
Build
```

Click the running build number, then **Console Output** to watch every stage execute live.

Expected: the build ends with `Finished: SUCCESS`. The first run takes 5 to 10 minutes because it also creates the Kind cluster and installs the Nginx Ingress Controller; later runs are faster because both steps become no-ops.

If the build fails, see Troubleshooting below before continuing.

## Step 20: Verify The App

From the EC2 terminal:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Open in a browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Dashboard data appears.
No CORS errors in the browser console.
```

## Step 21: Create The Jenkins Rollback Pipeline Job

```text
Dashboard
New Item
Name: launchboard-jenkins-rollback
Type: Pipeline
OK
```

Configure the job:

```text
Pipeline:
  Definition: Pipeline script from SCM
  SCM: Git
  Repository URL: git@github.com:ashraful2430/N-tier-application.git
  Credentials: github-jenkins-deploy-key
  Branch Specifier: */main
  Script Path: deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/Jenkinsfile.rollback
```

Click **Save**, then click **Build Now** once with the default parameter. Jenkins needs one initial run to discover the `choice` parameter declared in the Jenkinsfile before showing it as a "Build with Parameters" form on later runs — this is normal Jenkins behavior for any Pipeline-from-SCM job, not specific to this lab.

## Step 22: Test The Full CI/CD Loop

Make a visible change:

```bash
cd /opt/devops-launchboard/app-source
vim deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/configmap.yaml
```

Change `APP_NAME`:

```yaml
  APP_NAME: DevOps LaunchBoard API via Jenkins v2
```

Commit and push:

```bash
git add deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/configmap.yaml
git commit -m "test Jenkins CI/CD loop"
git push origin main
```

Within 5 minutes (the Poll SCM schedule from Step 18), Jenkins detects the new commit and starts a build automatically. Watch it under:

```text
Dashboard
launchboard-jenkins-deploy
```

No SSH session, no manual `kubectl` command, no manual "Build Now" click was needed for this deployment.

## Step 23: Test Rollback

```text
Dashboard
launchboard-jenkins-rollback
Build with Parameters
DEPLOYMENT: launchboard-backend
Build
```

Watch the console output: it shows the rollout history, rolls back, waits, and verifies. Repeat with `launchboard-frontend` if you want to test that Deployment too.

## Logs And Debugging

Jenkins itself:

```bash
sudo journalctl -u jenkins -n 100 --no-pager
sudo tail -n 100 /var/log/jenkins/jenkins.log
```

Pipeline build logs: Jenkins UI > job name > build number > Console Output.

Kubernetes checks:

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

Docker and Kind checks:

```bash
docker images | grep launchboard
kind get clusters
kubectl get nodes
```

## Troubleshooting

### Problem 1: Jenkins UI Is Unreachable On Port 8080

Common causes:

```text
Security group does not allow inbound 8080 from your IP.
Jenkins service is not running: sudo systemctl status jenkins
Your IP address changed since the security group rule was created.
```

### Problem 2: Pipeline Fails With "permission denied" On Docker Commands

The `jenkins` user is not in the `docker` group, or Jenkins was not restarted after Step 9.

```bash
groups jenkins
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Problem 3: Pipeline Fails At Checkout With "Permission denied (publickey)"

The Jenkins credential from Step 17 does not match the deploy key added to GitHub, or the deploy key was added to the wrong repository.

```bash
sudo -u jenkins ssh -T git@github.com -i /var/lib/jenkins/.ssh/known_hosts 2>&1 || true
```

Re-check that the public key pasted into GitHub matches `cat ~/jenkins_deploy_key.pub`, and that the private key pasted into the Jenkins credential matches `cat ~/jenkins_deploy_key`.

### Problem 4: Build Stuck Or Fails At "Create Kind Cluster If Missing"

```bash
sudo -u jenkins kind get clusters
sudo -u jenkins docker ps
```

If a previous failed build left a half-created cluster, delete it and let the next build recreate it cleanly:

```bash
sudo -u jenkins kind delete cluster --name launchboard-jenkins
```

### Problem 5: Pods Show ImagePullBackOff

The image was built but never loaded into the Kind node, or the manifest still has the literal placeholder string. Check:

```bash
kubectl -n devops-launchboard describe pod POD_NAME | tail -10
grep -r IMAGE_TAG_PLACEHOLDER deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/
```

If `grep` finds the placeholder still present after a build ran, the "Stamp Image Tag Into Manifests" stage did not run before "Deploy To Kind" — check the build's Console Output for the order stages actually executed in.

### Problem 6: Second Build's "Stamp Image Tag" Stage Silently Does Nothing

The `post { always { git checkout -- ... } }` block from Step 14 did not run on a previous failed build (for example, the build was manually aborted), so the placeholder is already gone from the workspace. Manually restore it:

```bash
cd /opt/devops-launchboard/app-source
git checkout -- deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-backend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-frontend-deployment.yaml \
  deployment/phase-07-cicd-self-hosted/phase-7-cicd-jenkins/k8s/launchboard-migration-job.yaml
```

### Problem 7: CORS Errors In Browser

```bash
kubectl -n devops-launchboard get configmap launchboard-config -o jsonpath='{.data.CORS_ORIGINS}'
```

Must exactly match the URL in the browser address bar. Re-run the deploy pipeline with the correct `PUBLIC_APP_URL` build parameter.

## Cleanup

Delete the Kubernetes app:

```bash
kubectl delete namespace devops-launchboard
```

Delete the Kind cluster:

```bash
sudo -u jenkins kind delete cluster --name launchboard-jenkins
```

Remove the two Jenkins jobs:

```text
Dashboard > launchboard-jenkins-deploy > Delete Pipeline
Dashboard > launchboard-jenkins-rollback > Delete Pipeline
```

Remove the GitHub deploy key:

```text
GitHub repository > Settings > Deploy keys > delete "jenkins-devops-launchboard"
```

Stop and uninstall Jenkins (if you are done with this server entirely):

```bash
sudo systemctl stop jenkins
sudo systemctl disable jenkins
sudo apt remove -y jenkins
```

Terminate the EC2 instance from the AWS Console.

## Production Checklist

```text
[ ] EC2 server created with port 8080 restricted to your IP
[ ] Docker installed and verified
[ ] kubectl and Kind installed
[ ] GitHub SSH key created and tested (for your own manual clone)
[ ] Repository cloned
[ ] Java and Jenkins installed
[ ] Jenkins unlocked, suggested plugins installed, admin user created
[ ] jenkins system user added to docker group and Jenkins restarted
[ ] jenkins system user verified to run docker ps successfully
[ ] Phase folders and root .dockerignore created
[ ] Dockerfile.backend, Dockerfile.frontend, nginx-frontend.conf created
[ ] kind-config.yaml created
[ ] All Kubernetes manifests created in k8s/
[ ] Jenkinsfile and Jenkinsfile.rollback created
[ ] Changes committed and pushed to main
[ ] Separate Jenkins-only GitHub deploy key created and added as a Jenkins credential
[ ] launchboard-jenkins-deploy Pipeline job created with Poll SCM
[ ] First pipeline run succeeded end to end
[ ] App verified in browser with no CORS errors
[ ] launchboard-jenkins-rollback Pipeline job created
[ ] Full CI/CD loop tested with a real code push
[ ] Rollback tested from the Jenkins UI
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Jenkins installation (Debian/Ubuntu) | https://www.jenkins.io/doc/book/installing/linux/#debianubuntu |
| Jenkins Pipeline syntax | https://www.jenkins.io/doc/book/pipeline/syntax/ |
| Jenkins Pipeline from SCM | https://www.jenkins.io/doc/book/pipeline/getting-started/#defining-a-pipeline-in-scm |
| Jenkins credentials | https://www.jenkins.io/doc/book/using/using-credentials/ |
| Jenkins Poll SCM cron syntax | https://www.jenkins.io/doc/book/pipeline/syntax/#cron-syntax |
| Jenkins built-in steps reference | https://www.jenkins.io/doc/pipeline/steps/ |
| Docker Engine Ubuntu install | https://docs.docker.com/engine/install/ubuntu/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Kustomize documentation | https://kustomize.io/ |
| Kubernetes Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| kubectl rollout | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/ |

## What To Do Next

Move to:

```text
Phase 8: EKS
```

Why:

This phase taught CI/CD with a self-hosted Jenkins server against a local Kind cluster, the Jenkins-flavored equivalent of the main Phase 7 guide's GitHub Actions pipeline. Phase 8 moves the Kubernetes platform itself to AWS EKS so you can learn managed Kubernetes, cloud networking, and cloud-native deployment — independent of which CI tool triggers it.
