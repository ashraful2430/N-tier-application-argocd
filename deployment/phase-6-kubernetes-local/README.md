# Phase 6: Kubernetes Local With Kind

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker is not installed yet.
- Kubernetes tools are not installed yet.
- Kind is not installed yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys the N-tier application into a local Kubernetes cluster created with Kind.

You will deploy:

- PostgreSQL database as a Kubernetes Deployment.
- PostgreSQL PersistentVolumeClaim for database storage.
- Kubernetes Secret for sensitive database values.
- Kubernetes ConfigMap for non-secret application values.
- Alembic migration Job.
- FastAPI backend Deployment with 2 replicas.
- Backend ClusterIP Service.
- React/Vite frontend Deployment with 2 replicas.
- Frontend ClusterIP Service.
- Nginx Ingress Controller.
- Ingress route for public browser traffic.
- Optional HPA example for backend autoscaling.

Architecture:

```text
Browser
  |
  | HTTP port 80 on EC2
  v
Kind control-plane port mapping
  |
  v
Ingress Nginx Controller
  |
  v
launchboard-frontend Service
  |
  v
launchboard-frontend Pods
  |
  | /api, /health, /ready
  v
launchboard-backend Service
  |
  v
launchboard-backend Pods
  |
  v
launchboard-db Service
  |
  v
PostgreSQL Pod + PVC
```

## When To Use This Architecture

Use local Kubernetes when:

- You want to learn Kubernetes before using EKS.
- You want a low-cost Kubernetes lab on one EC2 server.
- You want to understand Pods, Deployments, Services, ConfigMaps, Secrets, Jobs, Ingress, PVCs, probes, rollouts, and rollback.
- You want to test Kubernetes manifests before moving to cloud Kubernetes.

Do not use local Kubernetes when:

- You need real production high availability.
- You need managed node groups, cloud load balancers, and cloud storage.
- You need multiple worker nodes.
- You need production-grade database backups.

Important note:

Kind is excellent for learning and manifest validation. It is not a replacement for production Kubernetes platforms like EKS, GKE, AKS, or a properly operated self-managed Kubernetes cluster.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-6` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 25 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-6-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if you later test HTTPS |

Do not open these publicly:

```text
8000
5432
6443
```

Why:

- `8000` is backend traffic inside Kubernetes.
- `5432` is PostgreSQL traffic inside Kubernetes.
- `6443` is Kubernetes API traffic and should not be public in this student lab.

## Files Included In This Phase

```text
deployment/phase-6-kubernetes-local/
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
+-- kind-config.yaml
+-- nginx-frontend.conf
+-- README.md
```

The README shows all file contents inline so students can create the files manually while reading the guide.

## Tool Explanation

| Tool | Purpose |
| --- | --- |
| Docker | Builds container images and runs Kind nodes as containers. |
| Kind | Creates a local Kubernetes cluster using Docker containers as nodes. |
| kubectl | Controls Kubernetes resources from the terminal. |
| Kustomize | Applies multiple Kubernetes YAML files with one command through `kubectl apply -k`. |
| Nginx Ingress Controller | Receives public HTTP traffic and routes it to Kubernetes Services. |
| ConfigMap | Stores non-secret application configuration. |
| Secret | Stores sensitive configuration such as database password and database URL. |
| Deployment | Keeps application Pods running and supports rolling updates. |
| Service | Gives Pods a stable internal DNS name and virtual IP. |
| Job | Runs one-time tasks such as database migrations. |
| PVC | Requests persistent storage for PostgreSQL data. |
| Ingress | Defines public HTTP routing rules. |

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-6` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 25 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

Why this step exists:

Kind runs Kubernetes nodes as Docker containers. EC2 gives us the Linux server that runs Docker, Kind, kubectl, and the application workload.

Reference:

- AWS EC2 docs: https://docs.aws.amazon.com/ec2/
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 2: SSH Into EC2

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Command explanation:

- `chmod 400` makes the private key readable only by your user.
- `ssh -i` uses that private key to connect to the EC2 server.
- `ubuntu@YOUR_EC2_PUBLIC_IP` means you are logging in as the default Ubuntu user.

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

Reference:

- AWS SSH guide: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-linux-inst-ssh.html

## Step 3: Update Server And Install Base Tools

Run:

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim unzip jq ca-certificates gnupg lsb-release
```

Command explanation:

- `cd ~` moves to the Ubuntu user's home directory.
- `sudo apt update` refreshes Ubuntu package metadata.
- `sudo apt upgrade -y` installs available package updates.
- `git` is used to clone the repository.
- `curl` and `wget` download tools and test HTTP endpoints.
- `vim` is used to create and edit files.
- `unzip` extracts zip files if needed.
- `jq` formats JSON output from API responses.
- `ca-certificates` allows secure HTTPS package downloads.
- `gnupg` verifies signed package repositories.
- `lsb-release` helps identify Ubuntu release information.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/package-management

## Step 4: Install Docker Engine

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

Command explanation:

- `sudo install -m 0755 -d /etc/apt/keyrings` creates the secure apt keyring folder.
- `curl -fsSL ...` downloads Docker's official GPG key.
- `gpg --dearmor` converts the key into a format apt can use.
- `sudo chmod a+r` allows apt to read the Docker GPG key.
- `echo "deb ..." | sudo tee ...` adds Docker's official Ubuntu repository.
- `sudo apt update` refreshes packages again after adding Docker's repository.
- `docker-ce` installs Docker Engine.
- `docker-ce-cli` installs the Docker CLI.
- `containerd.io` installs the container runtime used by Docker.
- `docker-buildx-plugin` installs modern Docker build functionality.
- `systemctl enable docker` starts Docker automatically after reboot.
- `systemctl start docker` starts Docker now.
- `usermod -aG docker ubuntu` lets the `ubuntu` user run Docker without `sudo` after logging back in.

Log out and SSH back in:

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

Kind creates Kubernetes nodes as Docker containers. Without Docker, Kind cannot create the local Kubernetes cluster.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Install kubectl

Run:

```bash
cd ~
curl -LO "https://dl.k8s.io/release/stable.txt"
KUBECTL_VERSION=$(cat stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/kubectl
rm stable.txt
```

Command explanation:

- `curl -LO stable.txt` downloads the latest stable Kubernetes version number.
- `KUBECTL_VERSION=$(cat stable.txt)` stores that version in a shell variable.
- `curl -LO .../kubectl` downloads the kubectl binary for Linux AMD64.
- `chmod +x kubectl` makes the binary executable.
- `sudo mv kubectl /usr/local/bin/kubectl` places kubectl in the system PATH.
- `rm stable.txt` removes the temporary version file.

Verify:

```bash
kubectl version --client
```

Why this step exists:

`kubectl` is the command-line tool used to create, inspect, update, and delete Kubernetes resources.

Reference:

- Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/

## Step 6: Install Kind

Run:

```bash
cd ~
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/kind
```

Command explanation:

- `curl -Lo kind ...` downloads the Kind binary.
- `chmod +x kind` makes the binary executable.
- `sudo mv kind /usr/local/bin/kind` places Kind in the system PATH.

Verify:

```bash
kind version
```

Why this step exists:

Kind creates a local Kubernetes cluster using Docker containers as Kubernetes nodes.

Reference:

- Kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/

## Step 7: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-6-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `mkdir -p ~/.ssh` creates the SSH folder if it does not exist.
- `chmod 700 ~/.ssh` restricts SSH folder permissions.
- `ssh-keygen -t ed25519` creates a modern SSH key pair.
- `-C` adds a label so the key is easy to identify in GitHub.
- `-f` sets the key file path.
- `cat ...pub` prints the public key so you can copy it to GitHub.

Add the public key to GitHub:

```text
GitHub repository
Settings
Deploy keys
Add deploy key
```

Use:

| Field | Value |
| --- | --- |
| Title | `devops-launchboard-phase-6-ec2` |
| Key | Paste the public key |
| Allow write access | Unchecked |

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

The EC2 server needs GitHub access to clone the repository by SSH.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 8: Clone The Repository

Run:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Command explanation:

- `sudo mkdir -p /opt/devops-launchboard` creates a clean deployment folder under `/opt`.
- `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard` lets the `ubuntu` user manage this folder.
- `git clone ... app-source` clones the repository into a folder named `app-source`.
- `git branch --show-current` confirms which branch is checked out.

Expected:

```text
main
```

Reference:

- Git clone documentation: https://git-scm.com/docs/git-clone

## Step 9: Create Phase 6 Working Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-6-kubernetes-local/k8s
```

Command explanation:

- `cd /opt/devops-launchboard/app-source` moves into the cloned repository.
- `mkdir -p .../k8s` creates the Phase 6 folder and the Kubernetes manifest folder.

Why this folder exists:

The phase folder keeps Dockerfiles, Kind config, Nginx config, and Kubernetes manifests together.

## Step 10: Create Root `.dockerignore`

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
deployment/phase-4-docker-compose/.env
deployment/phase-5-docker-swarm/secrets/*
deployment/phase-6-kubernetes-local/k8s/secret.yaml
```

Why this file exists:

Docker builds use the repository root as the build context. `.dockerignore` keeps local dependencies, caches, build output, and secrets out of Docker images.

Reference:

- Docker build context: https://docs.docker.com/build/concepts/context/

## Step 11: Create Kind Config

Run:

```bash
vim deployment/phase-6-kubernetes-local/kind-config.yaml
```

Paste:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
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

- `kind: Cluster` tells Kind this file describes a cluster.
- `apiVersion: kind.x-k8s.io/v1alpha4` defines the Kind config API version.
- `nodes` defines the Kubernetes nodes Kind should create.
- `role: control-plane` creates one control-plane node.
- `kubeadmConfigPatches` customizes Kubernetes node initialization.
- `node-labels: ingress-ready=true` allows the Kind Ingress Nginx manifest to schedule the controller on this node.
- `extraPortMappings` maps EC2 host ports into the Kind node container.
- `hostPort: 80` lets public HTTP traffic reach the Kind cluster.
- `hostPort: 443` is reserved for HTTPS testing later.

## Step 12: Create Backend Dockerfile

Run:

```bash
vim deployment/phase-6-kubernetes-local/Dockerfile.backend
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

RUN groupadd --system app \
    && useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

RUN chown -R app:app /app /opt/venv

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

Line explanation:

- `FROM python:3.12-slim AS builder` starts a lightweight Python build stage.
- `PYTHONDONTWRITEBYTECODE=1` prevents Python from writing `.pyc` files.
- `PYTHONUNBUFFERED=1` makes logs appear immediately.
- `VIRTUAL_ENV=/opt/venv` defines where the Python virtual environment lives inside the image.
- `PATH="/opt/venv/bin:${PATH}"` makes `python`, `pip`, `uvicorn`, and `alembic` use the virtual environment first.
- `WORKDIR /app` sets `/app` as the working directory inside the image.
- `RUN python -m venv /opt/venv` creates the virtual environment during image build.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency and Alembic config files.
- `COPY backend/app ./app` copies backend application code.
- `COPY backend/alembic ./alembic` copies migration files.
- `pip install --no-cache-dir --upgrade pip` upgrades pip without storing cache.
- `pip install --no-cache-dir ".[dev]"` installs the app with dependencies needed to run Alembic migrations.
- `FROM python:3.12-slim AS runtime` starts a clean final runtime stage.
- `groupadd` and `useradd` create a non-root Linux user named `app`.
- `COPY --from=builder` copies only the prepared virtual environment and app files into the runtime image.
- `chown -R app:app` gives the non-root user ownership of app files.
- `USER app` runs the backend as non-root.
- `EXPOSE 8000` documents the backend container port.
- `HEALTHCHECK` checks the backend `/health` endpoint.
- `CMD` starts the FastAPI app with Uvicorn when the container starts.

## Step 13: Create Frontend Dockerfile

Run:

```bash
vim deployment/phase-6-kubernetes-local/Dockerfile.frontend
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

COPY deployment/phase-6-kubernetes-local/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a lightweight Node image only to build the frontend.
- `WORKDIR /app` sets the frontend build directory.
- `ARG VITE_API_URL=""` allows a build-time API URL value.
- `ENV VITE_API_URL=${VITE_API_URL}` passes the build argument to Vite.
- `COPY frontend/package*.json ./` copies package files first for better Docker layer caching.
- `RUN npm ci` installs exact dependencies from `package-lock.json`.
- `COPY frontend/ ./` copies the frontend source code.
- `RUN npm run build` creates the production frontend build.
- `FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime` uses a lightweight Nginx runtime designed to run without root privileges.
- `COPY ... default.conf` copies the frontend Nginx config.
- `COPY --from=builder --chown=101:101 /app/dist ...` copies the built frontend files and gives ownership to the unprivileged Nginx user.
- `EXPOSE 8080` documents the frontend container port.
- `HEALTHCHECK` checks the internal frontend health endpoint.
- `CMD` starts Nginx when the container starts.

Image review:

- The final frontend image does not include Node.js.
- Node is used only during the build stage.
- The runtime is Nginx Alpine, so it is lightweight.
- The runtime is unprivileged, so it fits Kubernetes `runAsNonRoot` settings.

Reference:

- Vite build docs: https://vite.dev/guide/build
- Nginx unprivileged image: https://hub.docker.com/r/nginxinc/nginx-unprivileged

## Step 14: Create Frontend Nginx Config

Run:

```bash
vim deployment/phase-6-kubernetes-local/nginx-frontend.conf
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

- `server` defines one Nginx virtual server.
- `listen 8080` makes Nginx listen on container port `8080`.
- `server_name _` catches any hostname.
- `root /usr/share/nginx/html` points Nginx to the built frontend files.
- `index index.html` sets the default frontend file.
- `client_max_body_size 10M` allows request bodies up to 10 MB.
- `location = /healthz` creates a simple frontend health endpoint.
- `location /api/` proxies API requests to the backend Kubernetes Service.
- `proxy_pass http://launchboard-backend:8000/api/` uses the backend Service DNS name.
- `proxy_set_header` lines preserve useful request metadata.
- `location = /health` proxies health checks to the backend.
- `location = /ready` proxies readiness checks to the backend.
- `location /` serves frontend routes and falls back to `index.html`.

Reference:

- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html

## Step 15: Create Kubernetes Manifests

Create each file from the repository root:

```bash
cd /opt/devops-launchboard/app-source
```

### 15.1 Create `namespace.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/namespace.yaml
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

Explanation:

- `apiVersion: v1` uses the core Kubernetes API.
- `kind: Namespace` creates a namespace.
- `metadata.name` sets the namespace name.
- Labels help identify resources that belong to this app.

### 15.2 Create `configmap.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/configmap.yaml
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

Replace:

```text
YOUR_EC2_PUBLIC_IP
```

Explanation:

- `kind: ConfigMap` stores non-secret values.
- `namespace` places it inside `devops-launchboard`.
- `data` contains environment variable values used by Pods.
- `CORS_ORIGINS` must match the browser URL.
- `POSTGRES_DB` and `POSTGRES_USER` are shared database settings.

### 15.3 Create `secret.example.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/secret.example.yaml
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

Explanation:

- This is an example file only.
- Do not commit real secret values to Git.
- The real Secret will be created using `kubectl create secret` later.
- `stringData` allows writing plain text values, and Kubernetes stores them as encoded Secret data.

### 15.4 Create `pvc.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/pvc.yaml
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

Explanation:

- `PersistentVolumeClaim` requests persistent storage.
- `ReadWriteOnce` means one node can mount the volume for read and write.
- `storage: 5Gi` requests 5 GB of storage for PostgreSQL data.

### 15.5 Create `launchboard-postgres-deployment.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-postgres-deployment.yaml
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
              cpu: 1000m
              memory: 1Gi
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: launchboard-postgres-pvc
```

Explanation:

- `kind: Deployment` keeps the PostgreSQL Pod running.
- `replicas: 1` runs one PostgreSQL Pod.
- `strategy: Recreate` prevents multiple PostgreSQL Pods from using the same local PVC at the same time.
- `selector.matchLabels` connects the Deployment to its Pods.
- `image: postgres:16-alpine` uses the lightweight PostgreSQL image.
- `env` loads database name, user, and password from ConfigMap and Secret.
- `volumeMounts` mounts persistent storage inside the PostgreSQL container.
- `readinessProbe` checks when PostgreSQL is ready to accept traffic.
- `livenessProbe` checks whether PostgreSQL is still alive.
- `resources.requests` reserves minimum CPU and memory.
- `resources.limits` prevents the Pod from using too many resources.
- `persistentVolumeClaim` connects the Pod to the PVC.

### 15.6 Create `launchboard-postgres-service.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-postgres-service.yaml
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

Explanation:

- `kind: Service` creates a stable internal endpoint.
- `type: ClusterIP` makes the database reachable only inside the cluster.
- `selector.app: launchboard-db` sends traffic to PostgreSQL Pods.
- `port: 5432` is the Service port.
- `targetPort: 5432` is the PostgreSQL container port.
- Other Pods can reach the database using `launchboard-db:5432`.

### 15.7 Create `launchboard-migration-job.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
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
          image: launchboard-backend:phase-6
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

Explanation:

- `kind: Job` runs a one-time task.
- `backoffLimit: 3` allows Kubernetes to retry failed migration Pods up to 3 times.
- `restartPolicy: OnFailure` restarts the migration Pod only if it fails.
- `image: launchboard-backend:phase-6` uses the backend image because Alembic is inside that image.
- `imagePullPolicy: IfNotPresent` tells Kubernetes to use the image loaded into Kind if it exists.
- `command` overrides the Dockerfile CMD for this Job.
- The `until` loop waits until PostgreSQL is reachable.
- `alembic upgrade head` applies database migrations.
- `envFrom` loads all values from the ConfigMap and Secret.

### 15.8 Create `launchboard-backend-deployment.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-deployment.yaml
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
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: backend
          image: launchboard-backend:phase-6
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
              cpu: 500m
              memory: 512Mi
```

Explanation:

- `replicas: 2` runs two backend Pods.
- `RollingUpdate` updates Pods gradually.
- `maxSurge: 1` allows one extra Pod during rollout.
- `maxUnavailable: 0` keeps all old Pods available until new Pods are ready.
- `runAsNonRoot: true` prevents the backend from running as root.
- `seccompProfile: RuntimeDefault` uses the container runtime's default syscall restrictions.
- `imagePullPolicy: IfNotPresent` works with images loaded into Kind.
- The startup command waits for PostgreSQL, then starts Uvicorn.
- `readinessProbe` controls when the Pod receives traffic.
- `livenessProbe` restarts the Pod if the backend becomes unhealthy.

### 15.9 Create `launchboard-backend-service.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-service.yaml
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

Explanation:

- This Service gives backend Pods a stable DNS name.
- The frontend Nginx container can reach the backend using `launchboard-backend:8000`.
- `ClusterIP` keeps the backend private inside Kubernetes.

### 15.10 Create `launchboard-frontend-deployment.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-deployment.yaml
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
          image: launchboard-frontend:phase-6
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
              cpu: 250m
              memory: 256Mi
```

Explanation:

- `replicas: 2` runs two frontend Pods.
- `runAsNonRoot: true` makes the frontend run as a non-root user.
- `runAsUser: 101` matches the unprivileged Nginx image user.
- `fsGroup: 101` helps the container access files as the same group.
- `containerPort: 8080` is where Nginx listens inside the Pod.
- Probes call `/healthz` to check if Nginx is working.
- Resource requests and limits keep the frontend lightweight.

### 15.11 Create `launchboard-frontend-service.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-service.yaml
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

Explanation:

- This Service gives frontend Pods a stable internal endpoint.
- Ingress sends browser traffic to this Service.
- `port: 80` is the Service port.
- `targetPort: 8080` is the frontend container port.

### 15.12 Create `ingress.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/ingress.yaml
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

Explanation:

- `kind: Ingress` defines public HTTP routing.
- `ingressClassName: nginx` tells Kubernetes to use the Nginx Ingress Controller.
- `path: /` sends all browser traffic to the frontend Service.
- The frontend Nginx container handles `/api`, `/health`, and `/ready` proxying to the backend.

### 15.13 Create `hpa.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/hpa.yaml
```

Paste:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: launchboard-backend
  namespace: devops-launchboard
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: launchboard-backend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Explanation:

- HPA means Horizontal Pod Autoscaler.
- It can scale backend Pods based on CPU usage.
- `minReplicas: 2` keeps at least two backend Pods.
- `maxReplicas: 5` allows scaling up to five backend Pods.
- `averageUtilization: 70` means Kubernetes tries to keep average CPU around 70%.

Note:

HPA needs metrics-server. In this guide, `hpa.yaml` is created as an example, but it is not included in the default `kustomization.yaml`. This keeps the main deployment clean for students.

### 15.14 Create `kustomization.yaml`

Run:

```bash
vim deployment/phase-6-kubernetes-local/k8s/kustomization.yaml
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
```

Explanation:

- `kind: Kustomization` tells kubectl this file groups multiple YAML manifests.
- `resources` lists all manifests to apply together.
- `secret.example.yaml` is not included because real secrets should be created manually.
- `hpa.yaml` is not included by default because metrics-server is not installed yet.

## Step 16: Create Kind Cluster

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-6-kubernetes-local
kind create cluster --name launchboard-local --config kind-config.yaml
```

Command explanation:

- `kind create cluster` creates a Kubernetes cluster.
- `--name launchboard-local` gives the cluster a clear name.
- `--config kind-config.yaml` applies the port mapping and node label configuration.

Verify:

```bash
kubectl get nodes
kubectl get pods -A
```

Why this step exists:

This creates the local Kubernetes cluster where the app will run.

## Step 17: Install Nginx Ingress Controller

Run:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait:

```bash
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
```

Command explanation:

- `kubectl apply -f URL` applies the official Kind Ingress Nginx manifest.
- `kubectl wait` waits until the Ingress Controller Pod is ready.
- `--namespace ingress-nginx` checks the namespace where the controller runs.
- `--selector=app.kubernetes.io/component=controller` selects the controller Pod.
- `--timeout=180s` waits up to 3 minutes.

Why this step exists:

Ingress resources need an Ingress Controller. This installs Nginx Ingress for Kind.

Reference:

- Kind ingress guide: https://kind.sigs.k8s.io/docs/user/ingress/
- Ingress Nginx docs: https://kubernetes.github.io/ingress-nginx/

## Step 18: Choose Image Deployment Method

You have two valid options.

### Option A: Build Images Locally And Load Them Into Kind

Use this option when students are building the app from source code on the EC2 server.

Run:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend -t launchboard-backend:phase-6 .
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-6 .
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
```

Command explanation:

- `docker build -f ...Dockerfile.backend` builds the backend image.
- `-t launchboard-backend:phase-6` tags the backend image.
- `.` sends the repository root as the Docker build context.
- `docker build -f ...Dockerfile.frontend` builds the frontend image.
- `--build-arg VITE_API_URL=` keeps the frontend API URL empty so the browser uses same-origin paths like `/api/summary`.
- `kind load docker-image` copies local Docker images into the Kind cluster.
- Kind nodes do not automatically see images from the EC2 host, so loading is required for local images.

Verify:

```bash
docker images | grep launchboard
```

### Option B: Use Published Images From Docker Hub Or Another Registry

Use this option when images are already pushed to a registry.

Example image names:

```text
ashik6251/launchboard-backend-k8s:v1
ashik6251/launchboard-frontend-k8s:v1
```

Update the Kubernetes manifests:

```bash
cd /opt/devops-launchboard/app-source
vim deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
vim deployment/phase-6-kubernetes-local/k8s/launchboard-backend-deployment.yaml
vim deployment/phase-6-kubernetes-local/k8s/launchboard-frontend-deployment.yaml
```

Set these image values:

```yaml
image: ashik6251/launchboard-backend-k8s:v1
```

Use the backend image in:

```text
launchboard-migration-job.yaml
launchboard-backend-deployment.yaml
```

Set the frontend image in:

```yaml
image: ashik6251/launchboard-frontend-k8s:v1
```

Use it in:

```text
launchboard-frontend-deployment.yaml
```

For public Docker Hub images, you do not need `kind load docker-image`.

Kubernetes will pull the images from the registry.

Recommended image pull policy for published version tags:

```yaml
imagePullPolicy: IfNotPresent
```

For a changing tag like `latest`, use:

```yaml
imagePullPolicy: Always
```

Production recommendation:

Use immutable version tags such as:

```text
v1
v2
2026-06-06
commit-sha
```

Avoid using `latest` for real deployments.

## Step 19: Create Namespace And Secret

Apply the namespace first:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/namespace.yaml
```

Create the real Secret:

```bash
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='CHANGE_ME_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Command explanation:

- `kubectl apply -f namespace.yaml` creates the namespace before namespaced resources are created.
- `kubectl create secret generic` creates a Kubernetes Secret.
- `--namespace devops-launchboard` stores the Secret in the app namespace.
- `--from-literal=POSTGRES_PASSWORD=...` stores the PostgreSQL password.
- `--from-literal=DATABASE_URL=...` stores the backend database connection string.

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
```

The password must match in both values.

Verify:

```bash
kubectl -n devops-launchboard get secret launchboard-secret
```

Why this step exists:

The Secret must exist before PostgreSQL, the migration Job, and backend Pods start.

## Step 20: Apply Kubernetes Manifests

Run:

```bash
cd /opt/devops-launchboard/app-source
kubectl apply -k deployment/phase-6-kubernetes-local/k8s
```

Command explanation:

- `kubectl apply -k` applies all manifests listed inside `kustomization.yaml`.
- This creates the ConfigMap, PVC, Deployments, Services, Job, and Ingress.

Why this step exists:

This is the main deployment command for the application.

## Step 21: Verify Kubernetes Resources

Run:

```bash
kubectl -n devops-launchboard get all
kubectl -n devops-launchboard get ingress
kubectl -n devops-launchboard get pvc
```

Wait for Deployments:

```bash
kubectl -n devops-launchboard rollout status deployment/launchboard-db
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-frontend
```

Check migration Job:

```bash
kubectl -n devops-launchboard get job launchboard-migrate
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Expected:

```text
PostgreSQL Pod Running
Migration Job Completed
Backend Pods Running
Frontend Pods Running
Ingress exists
PVC Bound
```

Command explanation:

- `kubectl get all` shows Pods, Services, Deployments, ReplicaSets, and Jobs.
- `kubectl get ingress` shows public routing rules.
- `kubectl get pvc` checks persistent storage status.
- `rollout status` waits until a Deployment finishes rollout.
- `logs job/launchboard-migrate` shows migration output.

## Step 22: Verify The App

Run from EC2:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Open in browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Dashboard data appears.
API works through /api.
No browser CORS error appears.
```

Why this step exists:

These commands verify the public traffic path:

```text
EC2 port 80
↓
Kind port mapping
↓
Ingress Nginx Controller
↓
Frontend Service
↓
Frontend Pod
↓
Backend Service
↓
Backend Pod
↓
PostgreSQL Service
↓
PostgreSQL Pod
```

## Step 23: Test Rollout And Rollback

Build and load a new backend image:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-6-kubernetes-local/Dockerfile.backend -t launchboard-backend:phase-6-v2 .
kind load docker-image launchboard-backend:phase-6-v2 --name launchboard-local
```

Update backend image:

```bash
kubectl -n devops-launchboard set image deployment/launchboard-backend backend=launchboard-backend:phase-6-v2
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Check rollout history:

```bash
kubectl -n devops-launchboard rollout history deployment/launchboard-backend
```

Rollback:

```bash
kubectl -n devops-launchboard rollout undo deployment/launchboard-backend
kubectl -n devops-launchboard rollout status deployment/launchboard-backend
```

Command explanation:

- `docker build ... phase-6-v2` creates a new backend image version.
- `kind load docker-image ...` loads the new image into Kind.
- `kubectl set image` changes the image used by the backend Deployment.
- `rollout status` waits for the update to complete.
- `rollout history` shows previous rollout revisions.
- `rollout undo` returns to the previous revision.

Why this step exists:

Kubernetes Deployments support rolling updates and rollback. This is a core production deployment concept.

Reference:

- Kubernetes deployments: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

## Optional Step: Apply HPA Example

HPA requires metrics-server.

Check if metrics are available:

```bash
kubectl top nodes
kubectl top pods -n devops-launchboard
```

If metrics are available, apply the HPA:

```bash
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/hpa.yaml
kubectl -n devops-launchboard get hpa
```

If `kubectl top` does not work, skip HPA for now. The main application deployment does not depend on HPA.

## Logs And Debugging

Useful commands:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard get pods -o wide
kubectl -n devops-launchboard describe pod POD_NAME
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard logs deployment/launchboard-frontend
kubectl -n devops-launchboard logs deployment/launchboard-db
kubectl -n devops-launchboard logs job/launchboard-migrate
kubectl -n devops-launchboard get events --sort-by=.metadata.creationTimestamp
```

Command explanation:

- `get pods` shows Pod status.
- `get pods -o wide` shows extra details like node and Pod IP.
- `describe pod` shows events, image errors, probe failures, and scheduling details.
- `logs deployment/...` shows logs from Pods managed by a Deployment.
- `logs job/...` shows migration logs.
- `get events` shows recent Kubernetes events in order.

Port-forward fallback:

```bash
kubectl -n devops-launchboard port-forward service/launchboard-frontend 8080:80
```

Then open:

```text
http://127.0.0.1:8080
```

Why this section exists:

Kubernetes troubleshooting usually starts with Pods, events, rollout status, and logs.

## Troubleshooting

### Problem 1: Pod Shows `ImagePullBackOff`

Check:

```bash
kubectl -n devops-launchboard get pods
kubectl -n devops-launchboard describe pod POD_NAME
```

Common causes:

```text
Local image was not loaded into Kind.
Image name in manifest does not match the built image tag.
Published image name is wrong.
Private registry credentials are missing.
```

Fix for local images:

```bash
kind load docker-image launchboard-backend:phase-6 --name launchboard-local
kind load docker-image launchboard-frontend:phase-6 --name launchboard-local
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

### Problem 2: Backend Cannot Connect To Database

Check:

```bash
kubectl -n devops-launchboard logs deployment/launchboard-backend
kubectl -n devops-launchboard get secret launchboard-secret
kubectl -n devops-launchboard get service launchboard-db
kubectl -n devops-launchboard get pods -l app=launchboard-db
```

Common causes:

```text
Secret was not created.
DATABASE_URL password does not match POSTGRES_PASSWORD.
PostgreSQL Pod is not ready.
PostgreSQL Service name is wrong.
```

### Problem 3: Ingress Does Not Work

Check:

```bash
kubectl get pods -n ingress-nginx
kubectl -n devops-launchboard get ingress
curl -I http://127.0.0.1
```

Common causes:

```text
Ingress Controller is not ready.
Kind cluster was created without port mappings.
AWS security group does not allow port 80.
Ingress resource points to the wrong Service.
```

### Problem 4: Migration Job Failed

Check:

```bash
kubectl -n devops-launchboard describe job launchboard-migrate
kubectl -n devops-launchboard logs job/launchboard-migrate
```

Common causes:

```text
Alembic is not installed in the backend image.
DATABASE_URL is wrong.
PostgreSQL is not ready.
Old database volume has old credentials or old schema state.
```

Lab fix after correcting the issue:

```bash
kubectl -n devops-launchboard delete job launchboard-migrate
kubectl apply -f deployment/phase-6-kubernetes-local/k8s/launchboard-migration-job.yaml
```

### Problem 5: ConfigMap Or Deployment Changes Do Not Show Up

Apply again:

```bash
kubectl apply -k deployment/phase-6-kubernetes-local/k8s
```

Restart Deployments if environment values changed:

```bash
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
kubectl -n devops-launchboard rollout restart deployment/launchboard-frontend
```

### Problem 6: Secret Needs To Be Recreated

Delete and recreate the Secret:

```bash
kubectl -n devops-launchboard delete secret launchboard-secret
kubectl create secret generic launchboard-secret \
  --namespace devops-launchboard \
  --from-literal=POSTGRES_PASSWORD='NEW_STRONG_PASSWORD' \
  --from-literal=DATABASE_URL='postgresql+asyncpg://launchboard_user:NEW_STRONG_PASSWORD@launchboard-db:5432/launchboard'
```

Restart affected resources:

```bash
kubectl -n devops-launchboard rollout restart deployment/launchboard-db
kubectl -n devops-launchboard rollout restart deployment/launchboard-backend
```

Important:

If PostgreSQL already initialized with an old password, changing only the Secret may not update the existing database user password. For a lab reset, delete the namespace and recreate the deployment.

## Cleanup

Delete app resources:

```bash
kubectl delete namespace devops-launchboard
```

Delete Kind cluster:

```bash
kind delete cluster --name launchboard-local
```

Remove Docker images:

```bash
docker rmi launchboard-backend:phase-6 launchboard-backend:phase-6-v2 launchboard-frontend:phase-6 || true
```

Optional Docker cleanup for lab servers:

```bash
docker system prune -f
```

AWS cleanup:

- Terminate the EC2 instance.
- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check AWS Billing.

Why cleanup matters:

Even if Kind runs locally, the EC2 server and AWS resources can still create charges if they are left running.

## Security Notes

- Do not expose PostgreSQL publicly.
- Do not expose backend directly.
- Use Secrets for passwords.
- Do not commit real Secret YAML files.
- Use Ingress as the public entry point.
- Use resource requests and limits.
- Use readiness and liveness probes.
- Run app containers as non-root where possible.
- Use versioned image tags instead of `latest`.
- Use managed database storage for serious production.
- Use HTTPS for real public deployments.

## Image Review

Backend image:

```text
Base image: python:3.12-slim
Build style: multi-stage
Runtime user: non-root app user
Runtime port: 8000
Includes Alembic: yes, through .[dev]
Suitable for this phase: yes
```

Frontend image:

```text
Build image: node:22-alpine
Runtime image: nginxinc/nginx-unprivileged:1.27-alpine
Node included in final image: no
Runtime user: non-root Nginx user
Runtime port: 8080
Suitable for this phase: yes
```

For a student-level production-style Kubernetes lab, both images are clean and lightweight enough. For real company production, add image scanning, CI/CD, SBOM generation, and signed images.

## Production Checklist

```text
[ ] EC2 security group exposes only 22, 80, and optionally 443
[ ] Docker installed
[ ] kubectl installed
[ ] Kind installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned with SSH
[ ] Root .dockerignore created
[ ] Kind config created
[ ] Backend Dockerfile created
[ ] Frontend Dockerfile created
[ ] Nginx config created
[ ] Kubernetes manifests created
[ ] CORS_ORIGINS updated
[ ] Kind cluster created
[ ] Ingress Controller installed
[ ] Images built and loaded into Kind, or published images configured
[ ] Namespace created
[ ] Secret created
[ ] Manifests applied
[ ] PostgreSQL rollout successful
[ ] Migration Job completed
[ ] Backend rollout successful
[ ] Frontend rollout successful
[ ] Ingress works
[ ] Public browser URL works
[ ] API works through /api
[ ] Rollout tested
[ ] Rollback tested
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Kubernetes docs | https://kubernetes.io/docs/ |
| kubectl install | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ |
| Kind quick start | https://kind.sigs.k8s.io/docs/user/quick-start/ |
| Kind ingress | https://kind.sigs.k8s.io/docs/user/ingress/ |
| Ingress Nginx | https://kubernetes.github.io/ingress-nginx/ |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Services | https://kubernetes.io/docs/concepts/services-networking/service/ |
| ConfigMaps | https://kubernetes.io/docs/concepts/configuration/configmap/ |
| Secrets | https://kubernetes.io/docs/concepts/configuration/secret/ |
| Jobs | https://kubernetes.io/docs/concepts/workloads/controllers/job/ |
| Persistent Volumes | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ |
| Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ |

## What To Do Next

Move to:

```text
Phase 7: CI/CD
```

Why:

Phase 6 teaches Kubernetes deployment manually. Phase 7 teaches how to automate checks, image builds, and deployment steps through CI/CD.
