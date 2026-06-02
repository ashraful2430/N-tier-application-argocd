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

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys the N-tier application with Docker Swarm:

- PostgreSQL as a Swarm service.
- A one-time migration service.
- FastAPI backend with 2 replicas.
- React/Vite frontend served by Nginx with 2 replicas.
- Swarm overlay network.
- Swarm secret for the PostgreSQL password.
- Swarm named volume for PostgreSQL data.
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

## When To Use This Architecture

Use Docker Swarm when:

- You want built-in Docker orchestration without Kubernetes.
- You want to learn services, replicas, stacks, secrets, overlay networks, rolling updates, and rollbacks.
- You want a small multi-service app with more orchestration than Docker Compose.
- You want a stepping stone before Kubernetes.

Do not use Docker Swarm when:

- You are deploying to a team already standardized on Kubernetes.
- You need the full Kubernetes ecosystem.
- You need managed cloud Kubernetes features like EKS add-ons, managed node groups, and Kubernetes-native GitOps.
- You need managed database high availability.

Important production note:

This guide uses a single-node Swarm for student learning. Real Swarm production usually uses multiple manager/worker nodes and images stored in a registry. A single-node Swarm teaches the concepts without charging students for several EC2 instances.

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
+-- secrets/
|   +-- db_password.example
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
+-- stack.yml
+-- README.md
```

The README shows all file contents inline so students can create the files while reading from GitHub.

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

Why this step exists:

The server needs basic tools for cloning the app, installing Docker, editing files, and testing HTTP endpoints.

Command explanation:

- `apt update` refreshes package metadata.
- `apt upgrade -y` applies updates.
- `git` clones the repository.
- `curl` tests URLs.
- `vim` creates and edits files.
- `jq` formats JSON output.
- `ca-certificates` and `gnupg` help verify secure package repositories.

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

Docker Engine provides both container runtime and Swarm mode.

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

The Docker images are built from the backend and frontend source code.

Reference:

- Git clone documentation: https://git-scm.com/docs/git-clone

## Step 7: Create Phase 5 Working Folders

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-5-docker-swarm/secrets
```

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
```

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
    && pip install --no-cache-dir .

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

Explanation:

- `builder` installs dependencies.
- `runtime` runs the final app.
- The app runs as non-root user `app`.
- Health check confirms the backend process responds on `/health`.

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
RUN npm ci

COPY frontend/ ./
RUN npm run build

FROM nginx:1.27-alpine AS runtime

RUN addgroup -S app \
    && adduser -S app -G app \
    && mkdir -p /var/cache/nginx/client_temp /var/cache/nginx/proxy_temp /var/cache/nginx/fastcgi_temp /var/cache/nginx/uwsgi_temp /var/cache/nginx/scgi_temp /var/run /tmp/nginx \
    && chown -R app:app /usr/share/nginx/html /var/cache/nginx /var/run /tmp/nginx

COPY deployment/phase-5-docker-swarm/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Explanation:

- Node builds the frontend.
- Nginx serves the built frontend.
- Nginx listens on container port `8080` so it can run as non-root.
- Swarm publishes this service on public port `80`.

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

Explanation:

- `/` serves frontend files.
- `/api/`, `/health`, and `/ready` proxy to the backend Swarm service.
- `launchboard-backend` is resolved by Docker service discovery.
- `try_files` supports frontend route refreshes.

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

Explanation:

- `launchboard-db` runs PostgreSQL.
- `POSTGRES_PASSWORD_FILE` tells PostgreSQL to read its password from a Swarm secret.
- `launchboard-migrate` runs Alembic once as a Swarm job.
- `launchboard-backend` runs 2 backend replicas.
- `launchboard-frontend` runs 2 frontend replicas and publishes port `80`.
- The backend command reads `/run/secrets/db_password` and builds `DATABASE_URL` inside the container.
- The password is not written directly in `stack.yml`.
- `update_config` controls rolling updates.
- `rollback_config` controls rollback behavior.
- `overlay` network lets Swarm services communicate through service names.
- The PostgreSQL volume persists database data.

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

Verify:

```bash
docker node ls
docker info | grep Swarm
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

Use the same password idea from the stack file, but choose a stronger real value for your lab.

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

Why this step exists:

This checks whether Swarm can understand the stack file before you deploy it.

## Step 18: Deploy The Stack

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-5-docker-swarm
docker stack deploy --resolve-image never -c stack.yml devops-launchboard
```

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

Why this step exists:

Scaling changes how many replicas a service should run. This is one of the core reasons to use an orchestrator.

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

Inspect network and secret:

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

### Problem 2: Secret Already Exists

Check:

```bash
docker secret ls
```

Remove and recreate in a lab:

```bash
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

### Problem 4: Browser Cannot Open App

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

## Production Checklist

```text
[ ] EC2 security group exposes only 22, 80, and optionally 443
[ ] Docker installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned with SSH
[ ] Root .dockerignore created
[ ] Backend Dockerfile created
[ ] Frontend Dockerfile created
[ ] Nginx config created
[ ] Swarm stack file created
[ ] CORS_ORIGINS updated in stack.yml
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
| Nginx proxy docs | https://nginx.org/en/docs/http/ngx_http_proxy_module.html |

## What To Do Next

Move to:

```text
Phase 6: Kubernetes Local
```

Why:

Swarm teaches orchestration in Docker’s native style. Kubernetes teaches the industry-standard orchestration model with Pods, Deployments, Services, ConfigMaps, Secrets, and Ingress.
