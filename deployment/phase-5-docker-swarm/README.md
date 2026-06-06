# Phase 5: Docker Swarm

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker is not installed yet.
- Docker Swarm is not initialized yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.
- You are using a single-node Swarm for learning.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys the N-tier application with Docker Swarm:

- PostgreSQL as a Swarm service.
- A one-time Alembic migration service.
- FastAPI backend service with 2 replicas.
- React/Vite frontend served by Nginx with 2 replicas.
- Swarm overlay network for private service communication.
- Docker secret for the PostgreSQL password.
- Named Docker volume for PostgreSQL data.
- Rolling update and rollback examples.

Architecture:

```text
Browser
  |
  | HTTP port 80 through Swarm routing mesh
  v
launchboard-frontend service, 2 replicas
  |
  | /api, /health, /ready
  v
launchboard-backend service, 2 replicas
  |
  | DATABASE_URL built from Docker secret
  v
launchboard-db service, 1 replica
```

## Important Concept

Docker Compose runs containers directly.

Docker Swarm runs services.

A Swarm service can have one or many replicas. Each replica runs as a task.

Simple comparison:

| Docker Compose | Docker Swarm |
|---|---|
| `container` | `service task` |
| `docker compose up` | `docker stack deploy` |
| `bridge network` | `overlay network` |
| `.env` file for local variables | Docker secrets for sensitive values |
| Mostly one server | One server or multiple servers |

This phase uses one EC2 server only, so students can learn Swarm without paying for multiple instances.

## When To Use This Architecture

Use Docker Swarm when:

- You want built-in Docker orchestration without Kubernetes.
- You want to learn services, replicas, stacks, secrets, overlay networks, rolling updates, and rollbacks.
- You want a small multi-service app with more orchestration than Docker Compose.
- You want a stepping stone before Kubernetes.

Do not use Docker Swarm when:

- Your team already uses Kubernetes.
- You need the full Kubernetes ecosystem.
- You need managed cloud Kubernetes features like EKS add-ons, managed node groups, and Kubernetes-native GitOps.
- You need managed database high availability.

Important production note:

This guide uses a single-node Swarm for student learning. Real Swarm production usually uses multiple manager and worker nodes, images stored in a registry, external backups, HTTPS, monitoring, and alerting.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-5` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-5-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if using SSL |

For this single-node lab, do not open these publicly:

```text
8000
5432
2377
7946
4789
```

Why:

- `8000` is backend traffic inside the Swarm network.
- `5432` is PostgreSQL traffic inside the Swarm network.
- `2377`, `7946`, and `4789` are Swarm cluster ports. They are only needed between Swarm nodes, not from the public internet.

## Files Included In This Phase

```text
deployment/phase-5-docker-swarm/
├── secrets/
│   └── db_password.example
├── Dockerfile.backend
├── Dockerfile.frontend
├── nginx-frontend.conf
├── stack.yml
└── README.md
```

The README shows all file contents inline so students can create the files while reading from GitHub.

## Production And Image Review

The backend image is production-style for this student project because it uses:

- `python:3.12-slim`.
- Multi-stage build.
- Python virtual environment inside `/opt/venv`.
- Non-root runtime user.
- Health check.
- No public backend port in the Swarm stack.

The frontend image is lightweight because it uses:

- `node:22-alpine` only for the build stage.
- `nginx:1.27-alpine` for the final runtime stage.
- Only static build files copied into the final image.


## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-5` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` |
| Storage | 20 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

Why this step exists:

Docker Swarm needs at least one Linux server. In this phase, the same EC2 instance acts as the Swarm manager and also runs the app services.

Tool explanation:

- EC2 provides the virtual Linux server.
- Security groups act like a cloud firewall.
- Port `22` is for SSH access.
- Port `80` is for public HTTP traffic.
- Port `443` is for HTTPS if SSL is added later.

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

- `chmod 400 devops-launchboard-key.pem` makes the private key readable only by you.
- `ssh` opens a secure terminal session to the EC2 server.
- `-i devops-launchboard-key.pem` tells SSH which private key to use.
- `ubuntu@YOUR_EC2_PUBLIC_IP` logs in as the `ubuntu` user on your EC2 public IP.

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

Why this step exists:

SSH gives you terminal access to the EC2 server.

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
- `sudo apt upgrade -y` installs available security and package updates.
- `sudo apt install -y ...` installs required tools without asking for confirmation.
- `git` clones the repository.
- `curl` and `wget` test URLs and download files.
- `vim` creates and edits files from the terminal.
- `unzip` extracts zip files if needed.
- `jq` formats JSON output from API tests.
- `ca-certificates` helps Linux trust HTTPS certificates.
- `gnupg` verifies repository signing keys.
- `lsb-release` helps detect Ubuntu release information.

Why this step exists:

The server needs basic tools for cloning the app, installing Docker, editing files, and testing HTTP endpoints.

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

- `cd ~` moves to the home directory.
- `sudo install -m 0755 -d /etc/apt/keyrings` creates the folder for apt signing keys.
- `curl -fsSL ...` downloads Docker's official GPG key.
- `sudo gpg --dearmor ...` converts the key into the format apt uses.
- `sudo chmod a+r ...` makes the key readable by apt.
- `echo "deb ..." | sudo tee ...` adds Docker's official Ubuntu repository.
- `sudo apt update` refreshes package metadata again, now including Docker's repository.
- `docker-ce` installs Docker Community Edition Engine.
- `docker-ce-cli` installs the Docker command line client.
- `containerd.io` installs the container runtime used by Docker.
- `docker-buildx-plugin` installs Docker's modern build plugin.
- `sudo systemctl enable docker` starts Docker automatically after reboot.
- `sudo systemctl start docker` starts Docker now.
- `sudo usermod -aG docker ubuntu` allows the `ubuntu` user to run Docker without `sudo` after logging back in.

Why use the official Docker repository:

You can use `sudo apt install docker.io -y` for quick labs. This guide uses Docker's official repository because it is more production-style and gives students the current Docker Engine packages.

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

Expected:

```text
Docker version ...
Swarm: inactive
```

Why this step exists:

Docker Engine provides both the container runtime and Swarm mode.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/
- Docker Swarm docs: https://docs.docker.com/engine/swarm/

## Step 5: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-5-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `mkdir -p ~/.ssh` creates the SSH folder if it does not exist.
- `chmod 700 ~/.ssh` allows only your user to access the SSH folder.
- `ssh-keygen -t ed25519` creates a modern SSH key pair.
- `-C "devops-launchboard-phase-5-ec2"` adds a label so you know what this key is for.
- `-f ~/.ssh/devops_launchboard_github_key` saves the key with a clear filename.
- `cat ...pub` prints the public key so you can add it to GitHub.

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
| Title | `devops-launchboard-phase-5-ec2` |
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

The EC2 server needs GitHub access to clone the repository with SSH.

Reference:

- GitHub SSH documentation: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 6: Clone The Repository

Run:

```bash
sudo mkdir -p /opt/devops-launchboard
sudo chmod 755 /opt/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard
cd /opt/devops-launchboard
git clone git@github.com:ashraful2430/N-tier-application.git app-source
cd app-source
git branch --show-current
```

Command explanation:

- `sudo mkdir -p /opt/devops-launchboard` creates the deployment parent directory.
- `sudo chmod 755 /opt/devops-launchboard` allows normal users to enter the directory.
- `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard` gives the `ubuntu` user ownership.
- `cd /opt/devops-launchboard` moves into the deployment directory.
- `git clone ... app-source` clones the repository into a folder named `app-source`.
- `cd app-source` moves into the cloned project.
- `git branch --show-current` confirms the current branch.

Expected:

```text
main
```

Why this step exists:

The Docker images are built from the backend and frontend source code.

Reference:

- Git clone documentation: https://git-scm.com/docs/git-clone

## Step 7: Create Phase 5 Working Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-5-docker-swarm/secrets
```

Command explanation:

- `cd /opt/devops-launchboard/app-source` moves to the project root.
- `mkdir -p deployment/phase-5-docker-swarm/secrets` creates the Swarm phase folder and a secrets example folder.

Why this folder exists:

The phase folder stores Swarm-specific files. The `secrets` folder stores only example secret content, not real production secrets.

## Step 8: Create Root `.dockerignore`

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
deployment/phase-5-docker-swarm/secrets/db_password
```

Line explanation:

- `.git` keeps Git history out of Docker builds.
- `.github` keeps GitHub workflow files out of images.
- `.venv` and `backend/.venv` keep local Python virtual environments out of images.
- `frontend/node_modules` keeps local frontend dependencies out of images.
- `frontend/dist` keeps old frontend build output out of images.
- `node_modules` ignores any root-level Node dependencies.
- `__pycache__`, `**/__pycache__`, and `*.pyc` ignore Python cache files.
- `.pytest_cache` and `.ruff_cache` ignore test and lint caches.
- `.env` and `.env.*` keep secret env files out of images.
- `deployment/phase-4-docker-compose/.env` ignores the Phase 4 real env file.
- `deployment/phase-5-docker-swarm/secrets/db_password` ignores any real Swarm secret file if a student creates one locally.

Why this file exists:

Docker builds use the repository root as the build context. `.dockerignore` keeps local dependencies, caches, build output, and secrets out of Docker images.

Reference:

- Docker build context: https://docs.docker.com/build/concepts/context/

## Step 9: Create Backend Dockerfile

Run:

```bash
vim deployment/phase-5-docker-swarm/Dockerfile.backend
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
- `PYTHONUNBUFFERED=1` makes logs appear immediately in Docker logs.
- `VIRTUAL_ENV=/opt/venv` defines where the Python virtual environment lives inside the container.
- `PATH="/opt/venv/bin:${PATH}"` makes the container use Python tools from the virtual environment first.
- `WORKDIR /app` sets `/app` as the working directory inside the image.
- `RUN python -m venv /opt/venv` creates the virtual environment during image build.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies dependency and Alembic config files.
- `COPY backend/app ./app` copies backend application code.
- `COPY backend/alembic ./alembic` copies database migration files.
- `pip install --no-cache-dir --upgrade pip` upgrades pip without keeping cache.
- `pip install --no-cache-dir ".[dev]"` installs the app and development extras, including Alembic for migration commands.
- `FROM python:3.12-slim AS runtime` creates a clean runtime stage.
- `groupadd` and `useradd` create a non-root app user.
- `COPY --from=builder` copies only the prepared virtual environment and app files from the builder stage.
- `chown -R app:app` gives the non-root user ownership.
- `USER app` runs the backend as a non-root user.
- `EXPOSE 8000` documents that the backend listens on container port `8000`.
- `HEALTHCHECK` checks if `/health` responds inside the container.
- `CMD` starts the FastAPI app with Uvicorn when the container starts.

Why `.[dev]` is used:

The Swarm migration service runs `alembic upgrade head`. If Alembic is in your dev dependencies, the image must install `.[dev]`. Later, if Alembic is moved to normal production dependencies, you can change this to `pip install --no-cache-dir .`.

Why this Dockerfile is production-style for this phase:

- It uses a slim Python base image.
- It uses multi-stage build.
- It uses a virtual environment.
- It runs as non-root.
- It includes a health check.
- It does not expose backend port publicly in the stack.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- FastAPI deployment: https://fastapi.tiangolo.com/deployment/

## Step 10: Create Frontend Dockerfile

Run:

```bash
vim deployment/phase-5-docker-swarm/Dockerfile.frontend
```

Paste:

```dockerfile
FROM node:22-alpine AS builder

WORKDIR /app

ARG VITE_API_URL=""
ENV VITE_API_URL=${VITE_API_URL}

COPY frontend/package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY frontend/ ./
RUN npm run build

FROM nginx:1.27-alpine AS runtime

COPY deployment/phase-5-docker-swarm/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Line explanation:

- `FROM node:22-alpine AS builder` uses a lightweight Node image only for building the frontend.
- `WORKDIR /app` sets the frontend build directory.
- `ARG VITE_API_URL=""` accepts a build-time API URL.
- `ENV VITE_API_URL=${VITE_API_URL}` makes the build argument available to Vite.
- `COPY frontend/package*.json ./` copies dependency files first to improve Docker layer caching.
- `RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi` uses `npm ci` when a lock file exists and falls back to `npm install` if not.
- `COPY frontend/ ./` copies frontend source code.
- `RUN npm run build` creates the production static build.
- `FROM nginx:1.27-alpine AS runtime` uses a lightweight Nginx image for serving static files.
- `COPY nginx-frontend.conf` replaces the default Nginx site config.
- `COPY --from=builder /app/dist /usr/share/nginx/html` copies only built static files into the final image.
- `EXPOSE 8080` documents that Nginx listens on container port `8080`.
- `HEALTHCHECK` checks the Nginx `/healthz` endpoint.
- `CMD` starts Nginx in the foreground.

Why this is lightweight:

The final image does not contain Node.js source dependencies or `node_modules`. It only contains Nginx and the compiled frontend files.


Reference:

- Vite build docs: https://vite.dev/guide/build
- Nginx docs: https://nginx.org/en/docs/

## Step 11: Create Nginx Config

Run:

```bash
vim deployment/phase-5-docker-swarm/nginx-frontend.conf
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

- `server { ... }` defines one Nginx virtual server.
- `listen 8080;` makes Nginx listen on container port `8080`.
- `server_name _;` acts as a default catch-all server.
- `root /usr/share/nginx/html;` points Nginx to the built frontend files.
- `index index.html;` serves `index.html` by default.
- `client_max_body_size 10M;` allows requests up to 10 MB.
- `location = /healthz` returns `ok` for the frontend container health check.
- `access_log off;` avoids noisy logs for health checks.
- `location /api/` proxies API calls to the backend Swarm service.
- `proxy_pass http://launchboard-backend:8000/api/;` sends API traffic to the backend service name.
- `proxy_http_version 1.1;` uses HTTP/1.1 for proxy traffic.
- `proxy_set_header Host $host;` forwards the original host header.
- `proxy_set_header X-Real-IP $remote_addr;` forwards the client IP.
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` keeps the proxy chain IP list.
- `proxy_set_header X-Forwarded-Proto $scheme;` forwards whether the original request used HTTP or HTTPS.
- `location = /health` proxies public health checks to backend `/health`.
- `location = /ready` proxies public readiness checks to backend `/ready`.
- `location /` serves frontend routes.
- `try_files $uri $uri/ /index.html;` makes React/Vite browser refresh work.

Why this file exists:

The frontend container is both the public web server and the reverse proxy to the backend.

Reference:

- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html

## Step 12: Create Secret Example File

Run:

```bash
vim deployment/phase-5-docker-swarm/secrets/db_password.example
```

Paste:

```text
CHANGE_ME_STRONG_PASSWORD
```

Why this file exists:

This example reminds students what the secret value should look like. Do not put the real database password in Git.

Important:

The real password should be created directly as a Docker secret in Step 16.

## Step 13: Create Swarm Stack File

Run:

```bash
vim deployment/phase-5-docker-swarm/stack.yml
```

Paste:

```yaml
services:
  launchboard-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: launchboard
      POSTGRES_USER: launchboard_user
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - launchboard-postgres-data:/var/lib/postgresql/data
    networks:
      - launchboard
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U launchboard_user -d launchboard"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "1.0"
          memory: 1G

  launchboard-migrate:
    image: launchboard-backend:phase-5
    environment:
      APP_NAME: DevOps LaunchBoard API
      APP_ENV: production
      POSTGRES_HOST: launchboard-db
      POSTGRES_DB: launchboard
      POSTGRES_USER: launchboard_user
      CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP
      SEED_DEMO_DATA: "false"
    secrets:
      - db_password
    networks:
      - launchboard
    command:
      - /bin/sh
      - -c
      - |
        until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
          echo "waiting for postgres"
          sleep 2
        done
        export DATABASE_URL="postgresql+asyncpg://$${POSTGRES_USER}:$$(cat /run/secrets/db_password)@$${POSTGRES_HOST}:5432/$${POSTGRES_DB}"
        alembic upgrade head
    deploy:
      mode: replicated-job
      replicas: 1
      restart_policy:
        condition: none

  launchboard-backend:
    image: launchboard-backend:phase-5
    environment:
      APP_NAME: DevOps LaunchBoard API
      APP_ENV: production
      POSTGRES_HOST: launchboard-db
      POSTGRES_DB: launchboard
      POSTGRES_USER: launchboard_user
      CORS_ORIGINS: http://YOUR_EC2_PUBLIC_IP
      SEED_DEMO_DATA: "true"
    secrets:
      - db_password
    networks:
      - launchboard
    command:
      - /bin/sh
      - -c
      - |
        until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
          echo "waiting for postgres"
          sleep 2
        done
        export DATABASE_URL="postgresql+asyncpg://$${POSTGRES_USER}:$$(cat /run/secrets/db_password)@$${POSTGRES_HOST}:5432/$${POSTGRES_DB}"
        exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      rollback_config:
        parallelism: 1
        delay: 10s
        order: stop-first
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "1.0"
          memory: 512M

  launchboard-frontend:
    image: launchboard-frontend:phase-5
    ports:
      - target: 8080
        published: 80
        protocol: tcp
        mode: ingress
    networks:
      - launchboard
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/healthz"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      rollback_config:
        parallelism: 1
        delay: 10s
        order: stop-first
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "0.5"
          memory: 256M

networks:
  launchboard:
    driver: overlay
    attachable: true

volumes:
  launchboard-postgres-data:

secrets:
  db_password:
    external: true
```

Before saving, replace:

```text
YOUR_EC2_PUBLIC_IP
```

Stack file explanation:

### `services`

```yaml
services:
```

This section defines Swarm services. A service is the desired state Swarm maintains. If a service says `replicas: 2`, Swarm tries to keep 2 tasks running.

### `launchboard-db`

```yaml
launchboard-db:
  image: postgres:16-alpine
```

This creates the PostgreSQL service using the official lightweight PostgreSQL image.

```yaml
environment:
  POSTGRES_DB: launchboard
  POSTGRES_USER: launchboard_user
  POSTGRES_PASSWORD_FILE: /run/secrets/db_password
```

This initializes PostgreSQL:

- `POSTGRES_DB` creates the database.
- `POSTGRES_USER` creates the database user.
- `POSTGRES_PASSWORD_FILE` tells PostgreSQL to read the password from the Docker secret file.

```yaml
secrets:
  - db_password
```

This mounts the `db_password` secret inside the container at:

```text
/run/secrets/db_password
```

```yaml
volumes:
  - launchboard-postgres-data:/var/lib/postgresql/data
```

This stores database data in a named volume so data survives container replacement.

```yaml
networks:
  - launchboard
```

This connects PostgreSQL to the private Swarm overlay network.

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U launchboard_user -d launchboard"]
```

This checks whether PostgreSQL is ready to accept connections.

```yaml
deploy:
  replicas: 1
```

This keeps one PostgreSQL task running.

```yaml
placement:
  constraints:
    - node.role == manager
```

This places PostgreSQL on the manager node. In this single-node lab, the manager is the only node.

### `launchboard-migrate`

This service runs Alembic migrations once.

```yaml
image: launchboard-backend:phase-5
```

It uses the same backend image because the backend image contains Alembic and the migration files.

```yaml
command:
  - /bin/sh
  - -c
  - |
```

This overrides the backend image `CMD` and runs a shell script instead.

```sh
until python -c "import socket; s=socket.create_connection(('launchboard-db', 5432), timeout=3); s.close()"; do
  echo "waiting for postgres"
  sleep 2
done
```

This waits until PostgreSQL is reachable.

Why this is needed:

Docker Swarm stack files do not use Compose-style `depends_on` health conditions the same way Docker Compose does. So the service command waits for PostgreSQL manually.

```sh
export DATABASE_URL="postgresql+asyncpg://$${POSTGRES_USER}:$$(cat /run/secrets/db_password)@$${POSTGRES_HOST}:5432/$${POSTGRES_DB}"
```

This builds `DATABASE_URL` inside the container using environment variables and the secret password.

The double dollar signs are important:

```text
$${POSTGRES_USER}
$$(cat /run/secrets/db_password)
```

They prevent Docker from trying to substitute those values too early when reading the stack file.

```sh
alembic upgrade head
```

This applies all database migrations.

```yaml
deploy:
  mode: replicated-job
  replicas: 1
```

This tells Swarm to run the migration as a job that completes instead of a long-running service.

### `launchboard-backend`

This service runs the FastAPI backend.

```yaml
deploy:
  replicas: 2
```

This asks Swarm to run 2 backend tasks.

```yaml
command:
  - /bin/sh
  - -c
  - |
```

The backend command waits for PostgreSQL, builds `DATABASE_URL` from the secret, and then starts Uvicorn.

```sh
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers
```

`exec` replaces the shell process with Uvicorn. This helps Docker handle signals correctly when stopping or updating containers.

```yaml
update_config:
  parallelism: 1
  delay: 10s
  order: start-first
  failure_action: rollback
```

This controls rolling updates:

- `parallelism: 1` updates one backend task at a time.
- `delay: 10s` waits 10 seconds between updates.
- `order: start-first` starts a new task before stopping the old one.
- `failure_action: rollback` rolls back automatically if the update fails.

```yaml
rollback_config:
  parallelism: 1
  delay: 10s
  order: stop-first
```

This controls how rollback happens.

### `launchboard-frontend`

This service runs Nginx and serves the frontend.

```yaml
ports:
  - target: 8080
    published: 80
    protocol: tcp
    mode: ingress
```

This publishes the frontend through Swarm routing mesh:

```text
EC2 public port 80 -> frontend service port 8080
```

```yaml
deploy:
  replicas: 2
```

This asks Swarm to run 2 frontend tasks.

### `networks`

```yaml
networks:
  launchboard:
    driver: overlay
    attachable: true
```

This creates a Swarm overlay network.

Service names become DNS names inside this network:

```text
launchboard-db
launchboard-backend
launchboard-frontend
```

### `volumes`

```yaml
volumes:
  launchboard-postgres-data:
```

This creates a named volume for PostgreSQL data.

### `secrets`

```yaml
secrets:
  db_password:
    external: true
```

This tells Swarm:

```text
The secret already exists. Do not create it from this stack file.
```

That is why Step 16 creates the secret before deploying the stack.

Reference:

- Docker stack deploy: https://docs.docker.com/reference/cli/docker/stack/deploy/
- Docker Swarm secrets: https://docs.docker.com/engine/swarm/secrets/
- Swarm services: https://docs.docker.com/engine/swarm/how-swarm-mode-works/services/

## Step 14: Build Backend And Frontend Images

Run:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-5-docker-swarm/Dockerfile.backend -t launchboard-backend:phase-5 .
docker build -f deployment/phase-5-docker-swarm/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-5 .
```

Command explanation:

- `cd /opt/devops-launchboard/app-source` moves to the project root.
- `docker build` builds a Docker image.
- `-f deployment/phase-5-docker-swarm/Dockerfile.backend` tells Docker which backend Dockerfile to use.
- `-t launchboard-backend:phase-5` names and tags the backend image.
- `.` sends the current project root as the build context.
- The frontend build command uses `Dockerfile.frontend`.
- `--build-arg VITE_API_URL=` keeps the frontend API URL empty so the frontend uses same-origin `/api` calls through Nginx.
- `-t launchboard-frontend:phase-5` names and tags the frontend image.

Verify:

```bash
docker images | grep launchboard
```

Why this step exists:

Swarm deploys services from images. Unlike Docker Compose, `docker stack deploy` does not build images automatically.

Important note:

This single-node lab uses local images. In a multi-node Swarm cluster, push images to a registry such as Docker Hub, Amazon ECR, or GitHub Container Registry so every Swarm node can pull them.

Reference:

- Docker build docs: https://docs.docker.com/reference/cli/docker/buildx/build/

## Step 15: Initialize Docker Swarm

Show the server private IP:

```bash
hostname -I
```

Pick the first private IP from the output and run:

```bash
docker swarm init --advertise-addr YOUR_PRIVATE_IP
```

Command explanation:

- `hostname -I` prints the IP addresses assigned to the EC2 server.
- `docker swarm init` initializes this Docker host as a Swarm manager.
- `--advertise-addr YOUR_PRIVATE_IP` tells Swarm which IP address other nodes would use to reach this manager.

For a single-node lab, use the EC2 private IP.

Verify:

```bash
docker node ls
docker info | grep Swarm
```

Expected:

```text
Swarm: active
```

Why this step exists:

Swarm mode turns Docker into an orchestrator. A Swarm manager can run services, replicas, secrets, overlay networks, rolling updates, and rollbacks.

Reference:

- Create a Swarm: https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/

## Step 16: Create Docker Secret

Run:

```bash
printf "CHANGE_ME_STRONG_PASSWORD" | docker secret create db_password -
```

Command explanation:

- `printf "CHANGE_ME_STRONG_PASSWORD"` prints the password without adding an extra newline.
- `|` pipes the password into the Docker command.
- `docker secret create db_password -` creates a Swarm secret named `db_password` from standard input.

Use a stronger real password in your lab.

Verify:

```bash
docker secret ls
docker secret inspect db_password
```

Why this step exists:

Docker secrets keep sensitive values out of the stack file. Services read the secret from `/run/secrets/db_password` inside the container.

Reference:

- Docker Swarm secrets: https://docs.docker.com/engine/swarm/secrets/

## Step 17: Validate Stack File

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-5-docker-swarm
docker stack config -c stack.yml
```

Command explanation:

- `cd ...` moves into the Phase 5 folder.
- `docker stack config -c stack.yml` validates and renders the final stack configuration.

Why this step exists:

This checks whether Swarm can understand the stack file before you deploy it.

## Step 18: Deploy The Stack

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-5-docker-swarm
docker stack deploy --resolve-image never -c stack.yml devops-launchboard
```

Command explanation:

- `docker stack deploy` deploys a group of Swarm services from a stack file.
- `--resolve-image never` tells Swarm not to contact a registry to resolve image digests.
- `-c stack.yml` chooses the stack file.
- `devops-launchboard` is the stack name.

Why `--resolve-image never` is used:

This lab uses images built locally on one EC2 server. This flag tells Swarm not to contact a registry to resolve the image digest.

Verify:

```bash
docker stack ls
docker stack services devops-launchboard
docker stack ps devops-launchboard
```

Expected:

```text
launchboard-db has 1 replica
launchboard-migrate completes
launchboard-backend has 2 replicas
launchboard-frontend has 2 replicas
```

## Step 19: Verify The App

Run from EC2:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Command explanation:

- `curl -I http://127.0.0.1` checks frontend HTTP response headers.
- `curl -s http://127.0.0.1/health | jq` checks backend health through the frontend proxy.
- `curl -s http://127.0.0.1/ready | jq` checks backend readiness through the frontend proxy.
- `curl -s http://127.0.0.1/api/summary | jq` checks an API endpoint through Nginx.
- `127.0.0.1` means the EC2 server itself.

Open in browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Dashboard data appears.
API works through /api.
No CORS error appears.
```

## Step 20: Scale A Service

Run:

```bash
docker service scale devops-launchboard_launchboard-backend=3
docker service ls
docker service ps devops-launchboard_launchboard-backend
```

Command explanation:

- `docker service scale ...=3` changes the desired backend replica count to 3.
- `docker service ls` lists all Swarm services.
- `docker service ps ...` lists the tasks for one service.

Why this step exists:

Scaling changes how many replicas a service should run. This is one of the core reasons to use an orchestrator.

Important:

This manual scale change can be overwritten if you redeploy the stack file with `replicas: 2`.

## Step 21: Rolling Update

Build a new backend image tag:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-5-docker-swarm/Dockerfile.backend -t launchboard-backend:phase-5-v2 .
```

Update the service:

```bash
docker service update --image launchboard-backend:phase-5-v2 --resolve-image never devops-launchboard_launchboard-backend
```

Watch rollout:

```bash
docker service ps devops-launchboard_launchboard-backend
```

Command explanation:

- `docker build ... -t launchboard-backend:phase-5-v2 .` builds a new backend image tag.
- `docker service update --image ...` updates the running Swarm service to use the new image.
- `--resolve-image never` prevents Swarm from checking a remote registry.
- `docker service ps ...` shows each backend task during the rollout.

Why this step exists:

Swarm replaces backend tasks gradually. The stack file says `parallelism: 1`, so only one backend replica updates at a time.

Reference:

- Rolling updates: https://docs.docker.com/engine/swarm/swarm-tutorial/rolling-update/

## Step 22: Rollback A Service

Run:

```bash
docker service rollback devops-launchboard_launchboard-backend
docker service ps devops-launchboard_launchboard-backend
```

Command explanation:

- `docker service rollback ...` rolls the service back to its previous version.
- `docker service ps ...` shows the rollback task status.

Why this step exists:

Rollback returns a service to its previous version if the new version fails or behaves incorrectly.

Reference:

- Docker service rollback: https://docs.docker.com/reference/cli/docker/service/rollback/

## Logs And Debugging

List services:

```bash
docker service ls
```

Inspect service tasks:

```bash
docker service ps devops-launchboard_launchboard-db
docker service ps devops-launchboard_launchboard-migrate
docker service ps devops-launchboard_launchboard-backend
docker service ps devops-launchboard_launchboard-frontend
```

Read logs:

```bash
docker service logs devops-launchboard_launchboard-db
docker service logs devops-launchboard_launchboard-migrate
docker service logs devops-launchboard_launchboard-backend
docker service logs devops-launchboard_launchboard-frontend
```

Follow live logs:

```bash
docker service logs -f devops-launchboard_launchboard-backend
```

Inspect network, secret, and volume:

```bash
docker network ls
docker secret ls
docker volume ls
```

Why this section exists:

Swarm runs services as tasks. When something fails, `docker service ps` shows task state, and `docker service logs` shows runtime logs.

## Troubleshooting

### Problem 1: Stack Service Does Not Start

Check:

```bash
docker stack ps devops-launchboard
docker service logs devops-launchboard_launchboard-backend
```

Common causes:

```text
Image was not built.
Secret was not created.
Stack file has wrong service name.
Backend cannot connect to PostgreSQL.
```

Fix checklist:

```bash
docker images | grep launchboard
docker secret ls
docker network ls
docker stack services devops-launchboard
```

### Problem 2: Secret Already Exists

Check:

```bash
docker secret ls
```

Remove and recreate in a lab:

```bash
docker stack rm devops-launchboard
sleep 20
docker secret rm db_password
printf "CHANGE_ME_STRONG_PASSWORD" | docker secret create db_password -
```

Important:

You cannot remove a secret while a running service is using it. Remove the stack first if needed.

### Problem 3: Local Image Not Found

Check:

```bash
docker images | grep launchboard
```

Fix:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-5-docker-swarm/Dockerfile.backend -t launchboard-backend:phase-5 .
docker build -f deployment/phase-5-docker-swarm/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-5 .
```

### Problem 4: Migration Service Fails

Check:

```bash
docker service ps devops-launchboard_launchboard-migrate
docker service logs devops-launchboard_launchboard-migrate
```

Common causes:

```text
Alembic is not installed in the backend image.
Database password secret does not match PostgreSQL.
Database service is not reachable.
Migration files are missing from the image.
```

Recommended fix:

Make sure the backend Dockerfile uses:

```dockerfile
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir ".[dev]"
```

Then rebuild the backend image and redeploy the stack.

### Problem 5: Browser Cannot Open App

Check:

```bash
curl -I http://127.0.0.1
docker service ps devops-launchboard_launchboard-frontend
```

Common causes:

```text
AWS security group missing port 80.
Frontend service is not running.
Stack did not publish port 80.
```

### Problem 6: Frontend Loads But API Fails

Check:

```bash
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/api/summary | jq
docker service logs devops-launchboard_launchboard-frontend
docker service logs devops-launchboard_launchboard-backend
```

Common causes:

```text
Backend service is not healthy.
Nginx proxy target is wrong.
CORS_ORIGINS still contains YOUR_EC2_PUBLIC_IP instead of the real IP.
Database migration failed.
```

### Problem 7: Old Database Password Still Used

Cause:

PostgreSQL stores initialized data in the named volume. If you change the password secret after the database was already initialized, the old database volume may still use the old password.

Lab fix if you do not need old data:

```bash
docker stack rm devops-launchboard
sleep 30
docker volume rm devops-launchboard_launchboard-postgres-data || true
docker secret rm db_password
printf "NEW_STRONG_PASSWORD" | docker secret create db_password -
docker stack deploy --resolve-image never -c stack.yml devops-launchboard
```

## Rollback Plan

Rollback one service:

```bash
docker service rollback devops-launchboard_launchboard-backend
```

Remove the stack if the whole deployment is broken:

```bash
docker stack rm devops-launchboard
```

Wait until services are removed:

```bash
docker service ls
```

Deploy a previous Git version:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
docker build -f deployment/phase-5-docker-swarm/Dockerfile.backend -t launchboard-backend:phase-5 .
docker build -f deployment/phase-5-docker-swarm/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-5 .
cd deployment/phase-5-docker-swarm
docker stack deploy --resolve-image never -c stack.yml devops-launchboard
```

Why rollback exists:

A production deployment should always have a way back to a known good version.

## Cleanup

Remove the stack:

```bash
docker stack rm devops-launchboard
```

Wait until services disappear:

```bash
watch docker service ls
```

Remove secret after the stack is gone:

```bash
docker secret rm db_password
```

Remove Swarm mode:

```bash
docker swarm leave --force
```

Remove images:

```bash
docker rmi launchboard-backend:phase-5 launchboard-backend:phase-5-v2 launchboard-frontend:phase-5 || true
```

Remove PostgreSQL data volume:

```bash
docker volume rm devops-launchboard_launchboard-postgres-data || true
```

Important:

Removing the volume deletes database data.

Full Docker lab cleanup if this EC2 server is only used for this lab:

```bash
docker system prune -a --volumes
```

AWS cleanup:

- Terminate the EC2 instance.
- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check the AWS Billing dashboard.

Reference:

- AWS Billing: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/billing-what-is.html
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Security Notes

- Do not open PostgreSQL port `5432` publicly.
- Do not open backend port `8000` publicly.
- Do not expose Swarm cluster ports to the internet.
- Use Docker secrets for sensitive values.
- Do not commit real secret files.
- Use a registry for multi-node Swarm.
- Use HTTPS for real public apps.
- Use managed PostgreSQL for serious production workloads.
- Use backups before deleting Docker volumes.

## Production Checklist

```text
[ ] EC2 security group exposes only 22, 80, and optionally 443
[ ] Docker installed from official Docker repository
[ ] Docker service enabled and running
[ ] GitHub SSH key created and tested
[ ] Repository cloned with SSH
[ ] Root .dockerignore created
[ ] Backend Dockerfile created with .[dev] dependency install
[ ] Frontend Dockerfile created with stable official Nginx runtime behavior
[ ] Nginx config created
[ ] Secret example file created
[ ] Swarm stack file created
[ ] YOUR_EC2_PUBLIC_IP replaced in stack.yml
[ ] Backend image built
[ ] Frontend image built
[ ] Docker Swarm initialized
[ ] Docker secret created
[ ] Stack config validates
[ ] Stack deployed
[ ] Database service running
[ ] Migration job completed
[ ] Backend service has desired replicas
[ ] Frontend service has desired replicas
[ ] Public browser URL works
[ ] API works through /api
[ ] Rolling update tested
[ ] Rollback tested
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Docker Swarm overview | https://docs.docker.com/engine/swarm/ |
| Create a Swarm | https://docs.docker.com/engine/swarm/swarm-tutorial/create-swarm/ |
| Deploy a stack | https://docs.docker.com/reference/cli/docker/stack/deploy/ |
| Swarm services | https://docs.docker.com/engine/swarm/how-swarm-mode-works/services/ |
| Swarm secrets | https://docs.docker.com/engine/swarm/secrets/ |
| Rolling updates | https://docs.docker.com/engine/swarm/swarm-tutorial/rolling-update/ |
| Dockerfile reference | https://docs.docker.com/reference/dockerfile/ |
| PostgreSQL image | https://hub.docker.com/_/postgres |
| FastAPI deployment | https://fastapi.tiangolo.com/deployment/ |
| Vite production build | https://vite.dev/guide/build |
| Nginx proxy docs | https://nginx.org/en/docs/http/ngx_http_proxy_module.html |

## What To Do Next

Move to:

```text
Phase 6: Kubernetes Local
```

Why:

Swarm teaches orchestration in Docker's native style. Kubernetes teaches the industry-standard orchestration model with Pods, Deployments, Services, ConfigMaps, Secrets, and Ingress.
