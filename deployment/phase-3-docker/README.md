# Phase 3: Docker Single Container Deployment

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server.

You do not need to complete Phase 1 or Phase 2 before using this phase.

This guide assumes:

- You have a fresh AWS EC2 server.
- You have not installed Docker yet.
- You have not cloned this project on the server yet.
- You will type each command manually.
- You will create files with `vim`.
- You will not use shell scripts.
- You will run each service as its own Docker container by hand.

The goal of this phase is to learn Docker images and Docker containers before Docker Compose.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys:

- PostgreSQL in a Docker container.
- FastAPI backend in a Docker container.
- React/Vite frontend built into an Nginx Docker container.
- A Docker network so containers can talk to each other by container name.
- A Docker volume so PostgreSQL data survives container restarts.

Architecture:

```text
Browser
  |
  | HTTP port 80
  v
Frontend Nginx container
  |
  | /api, /health, /ready
  v
Backend FastAPI container
  |
  | PostgreSQL connection
  v
PostgreSQL container
```

## When To Use This Architecture

Use this architecture when:

- You want to learn how Docker images are built.
- You want to understand `docker build`, `docker run`, networks, volumes, logs, and ports.
- You want a small production-style deployment without Docker Compose yet.
- You want to package backend and frontend separately.
- You want to prepare for Docker Compose, Swarm, Kubernetes, and EKS.

Do not use this architecture when:

- You need many containers managed together every day.
- You need automatic restarts, rollbacks, and service discovery at scale.
- You need multi-server orchestration.
- You want easier environment management.

For real teams, Docker Compose is usually easier than manually running many `docker run` commands. That is why Phase 4 comes next.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-3` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.micro` or `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-3-sg` |
| SSH | Port `22`, your IP only |
| HTTP | Port `80`, anywhere |
| HTTPS | Port `443`, anywhere if you later add SSL |

Do not open these ports publicly:

```text
8000
5432
```

Why:

- Port `8000` is the backend container. The frontend Nginx container should proxy to it.
- Port `5432` is PostgreSQL. Databases should not be public.

## Files Included In This Phase

```text
deployment/phase-3-docker/
+-- env/
|   +-- backend.docker.env.example
|   +-- frontend.build.env.example
+-- .dockerignore
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
+-- README.md
```

These files are provided in the repository so students can inspect them. The README also shows the full file contents because students may be reading this guide from GitHub in a browser.

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-3` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.micro` or `t3.small` |
| Storage | 20 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Anywhere |
| HTTPS | 443 | Anywhere |

Why this step exists:

EC2 is the Linux server that runs Docker. Docker containers still need a machine underneath them.

## Step 2: SSH Into EC2

Run from your local terminal:

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

SSH gives you terminal access to the server where Docker will be installed and containers will run.

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

Why each command exists:

- `sudo apt update` refreshes Ubuntu package information.
- `sudo apt upgrade -y` installs available security and package updates.
- `git` clones the project.
- `curl` tests URLs and downloads setup files.
- `vim` creates and edits files manually.
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

Log out and SSH back in so the Docker group permission applies:

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

Docker Engine builds images and runs containers. Adding `ubuntu` to the `docker` group lets students run `docker` commands without typing `sudo` every time.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-3-ec2" -f ~/.ssh/devops_launchboard_github_key
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
| Title | `devops-launchboard-phase-3-ec2` |
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

The EC2 server needs permission to clone the private or protected GitHub repository using SSH.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

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

The Dockerfiles use the repository root as the build context. That means Docker can copy files from `backend`, `frontend`, and `deployment/phase-3-docker`.

Reference:

- Git clone docs: https://git-scm.com/docs/git-clone

## Step 7: Create Phase 3 Files With Vim

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-3-docker/env
```

Why this folder exists:

This folder keeps all Docker-specific files for Phase 3 in one place. Students can copy the files later, compare them with the README, or reuse them in the next phases.

### Create `.dockerignore`

Run:

```bash
vim deployment/phase-3-docker/.dockerignore
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
deployment/phase-4-docker-compose/volumes
```

Explanation:

- `.git` and `.github` are not needed inside Docker images.
- Virtual environments and `node_modules` are rebuilt inside Docker.
- `frontend/dist` is generated during the Docker build.
- `.env` files are excluded so secrets do not get baked into images.
- Cache folders are excluded to keep images smaller and cleaner.

Reference:

- Docker build context docs: https://docs.docker.com/build/concepts/context/

### Create Backend Dockerfile

Run:

```bash
vim deployment/phase-3-docker/Dockerfile.backend
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
ENV SEED_DEMO_DATA=false

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

- `builder` installs Python dependencies in a virtual environment.
- `runtime` keeps the final image focused on running the app.
- `PYTHONDONTWRITEBYTECODE=1` avoids writing `.pyc` files.
- `PYTHONUNBUFFERED=1` makes logs appear immediately in `docker logs`.
- `COPY backend/...` copies only backend code needed by FastAPI and Alembic.
- `pip install --no-cache-dir` avoids keeping pip cache inside the image.
- `USER app` runs the backend as a non-root user.
- `EXPOSE 8000` documents the backend port.
- `HEALTHCHECK` lets Docker report whether the backend is healthy.
- `CMD` starts Uvicorn.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- FastAPI deployment: https://fastapi.tiangolo.com/deployment/
- Uvicorn deployment: https://www.uvicorn.org/deployment/

### Create Frontend Dockerfile

Run:

```bash
vim deployment/phase-3-docker/Dockerfile.frontend
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

COPY deployment/phase-3-docker/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Explanation:

- The Node stage builds the Vite frontend.
- `ARG VITE_API_URL=""` makes frontend API calls use same-origin paths like `/api/summary`.
- `npm ci` installs exact dependencies from `package-lock.json`.
- The Nginx stage serves static production files.
- Nginx listens on container port `8080` so it can run as a non-root user.
- Public traffic will still use EC2 port `80`.

Reference:

- Vite build docs: https://vite.dev/guide/build
- Nginx docs: https://nginx.org/en/docs/

### Create Frontend Nginx Config

Run:

```bash
vim deployment/phase-3-docker/nginx-frontend.conf
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

- `listen 8080` lets Nginx run inside the container without root.
- `root` points to the built frontend files.
- `/healthz` is a simple container health endpoint.
- `/api/`, `/health`, and `/ready` proxy to the backend container.
- `launchboard-backend` works because both containers are on the same Docker network.
- `try_files` supports frontend routes after browser refresh.

Reference:

- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- Nginx serving static content: https://docs.nginx.com/nginx/admin-guide/web-server/serving-static-content/

### Create Backend Docker Env Example

Run:

```bash
vim deployment/phase-3-docker/env/backend.docker.env.example
```

Paste:

```env
APP_NAME=DevOps LaunchBoard API
APP_ENV=production
DATABASE_URL=postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-postgres:5432/launchboard
CORS_ORIGINS=http://YOUR_EC2_PUBLIC_IP
SEED_DEMO_DATA=true
```

Explanation:

- `DATABASE_URL` uses `launchboard-postgres` because that is the PostgreSQL container name.
- `CORS_ORIGINS` must match the browser URL.
- `SEED_DEMO_DATA=true` is useful for student labs because it loads sample dashboard data.

### Create Frontend Build Env Example

Run:

```bash
vim deployment/phase-3-docker/env/frontend.build.env.example
```

Paste:

```env
VITE_API_URL=
```

Explanation:

An empty `VITE_API_URL` makes the frontend call relative URLs. For example, the browser calls `/api/summary`, and the frontend Nginx container proxies that request to the backend.

## Step 8: Create Real Backend Env File

Run:

```bash
cd /opt/devops-launchboard/app-source
cp deployment/phase-3-docker/env/backend.docker.env.example deployment/phase-3-docker/env/backend.docker.env
vim deployment/phase-3-docker/env/backend.docker.env
```

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
YOUR_EC2_PUBLIC_IP
```

Why this step exists:

The example file is safe to commit. The real env file contains real lab values and should stay on the server.

## Step 9: Build Docker Images

Run from the repository root:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-3-docker/Dockerfile.backend -t launchboard-backend:phase-3 .
docker build -f deployment/phase-3-docker/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-3 .
```

Verify:

```bash
docker images | grep launchboard
```

Why this step exists:

Images are the packaged application. A container is a running instance of an image.

Reference:

- Docker build docs: https://docs.docker.com/reference/cli/docker/buildx/build/

## Step 10: Create Docker Network And Volume

Run:

```bash
docker network create launchboard-net
docker volume create launchboard-postgres-data
```

Verify:

```bash
docker network ls
docker volume ls
```

Why this step exists:

The network lets containers find each other by name. The volume stores PostgreSQL data outside the container filesystem, so deleting and recreating the PostgreSQL container does not immediately delete the database data.

Reference:

- Docker networking: https://docs.docker.com/engine/network/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/

## Step 11: Run PostgreSQL Container

Run:

```bash
docker run -d \
  --name launchboard-postgres \
  --network launchboard-net \
  -e POSTGRES_DB=launchboard \
  -e POSTGRES_USER=launchboard_user \
  -e POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD \
  -v launchboard-postgres-data:/var/lib/postgresql/data \
  postgres:16-alpine
```

Use the same password you placed in `backend.docker.env`.

Verify:

```bash
docker ps
docker logs launchboard-postgres
```

Why this step exists:

The backend needs a database. PostgreSQL runs as a container in this phase instead of being installed directly on Ubuntu.

Reference:

- PostgreSQL Docker image: https://hub.docker.com/_/postgres

## Step 12: Run Database Migrations

Run:

```bash
cd /opt/devops-launchboard/app-source
docker run --rm \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  launchboard-backend:phase-3 \
  alembic upgrade head
```

Why this step exists:

The backend image includes Alembic. This one-time container starts, creates the database tables, and exits.

## Step 13: Run Backend Container

Run:

```bash
cd /opt/devops-launchboard/app-source
docker run -d \
  --name launchboard-backend \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  --restart unless-stopped \
  launchboard-backend:phase-3
```

Verify:

```bash
docker ps
docker logs launchboard-backend
docker inspect --format='{{json .State.Health}}' launchboard-backend | jq
```

Why this step exists:

This starts the FastAPI backend as a long-running container. It is not exposed publicly because only the frontend Nginx container needs to reach it.

## Step 14: Run Frontend Container

Run:

```bash
docker run -d \
  --name launchboard-frontend \
  --network launchboard-net \
  -p 80:8080 \
  --restart unless-stopped \
  launchboard-frontend:phase-3
```

Verify:

```bash
docker ps
docker logs launchboard-frontend
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Why this step exists:

The frontend container is the public entry point. It serves the browser app and proxies API requests to the backend container.

## Step 15: Verify From Browser

Open:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Dashboard data appears.
API requests go through /api.
No browser CORS errors.
```

## Logs And Debugging

Useful commands:

```bash
docker ps
docker logs launchboard-postgres
docker logs launchboard-backend
docker logs launchboard-frontend
docker inspect launchboard-backend | jq
docker network inspect launchboard-net | jq
docker exec -it launchboard-postgres psql -U launchboard_user -d launchboard
```

Common restart commands:

```bash
docker restart launchboard-postgres
docker restart launchboard-backend
docker restart launchboard-frontend
```

Why this section exists:

Docker problems are usually visible in container logs, container health, or network inspection. Checking those first saves time.

## Rollback Plan

Stop the current containers:

```bash
docker stop launchboard-frontend launchboard-backend
docker rm launchboard-frontend launchboard-backend
```

Rebuild from a previous Git commit:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
docker build -f deployment/phase-3-docker/Dockerfile.backend -t launchboard-backend:phase-3 .
docker build -f deployment/phase-3-docker/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-3 .
```

Run migrations and containers again:

```bash
docker run --rm \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  launchboard-backend:phase-3 \
  alembic upgrade head

docker run -d \
  --name launchboard-backend \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  --restart unless-stopped \
  launchboard-backend:phase-3

docker run -d \
  --name launchboard-frontend \
  --network launchboard-net \
  -p 80:8080 \
  --restart unless-stopped \
  launchboard-frontend:phase-3
```

Rollback is important because every production deployment needs a recovery path.

## Cleanup

Use cleanup when the lab is finished:

```bash
docker stop launchboard-frontend launchboard-backend launchboard-postgres || true
docker rm launchboard-frontend launchboard-backend launchboard-postgres || true
docker network rm launchboard-net || true
docker volume rm launchboard-postgres-data || true
docker rmi launchboard-backend:phase-3 launchboard-frontend:phase-3 || true
```

Then terminate the EC2 instance from the AWS Console if you no longer need it.

Cost reminder:

- Running EC2 instances can cost money.
- EBS volumes can cost money.
- Unused Elastic IPs can cost money.

Reference:

- AWS Billing: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/billing-what-is.html
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Production Checklist

```text
[ ] EC2 security group exposes only 22, 80, and optionally 443
[ ] Docker Engine installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned with SSH
[ ] Dockerfiles created with vim
[ ] .dockerignore excludes secrets and heavy folders
[ ] Backend image builds successfully
[ ] Frontend image builds successfully
[ ] Docker network created
[ ] Docker volume created
[ ] PostgreSQL container running
[ ] Migrations completed
[ ] Backend container healthy
[ ] Frontend container healthy
[ ] Public browser URL works
[ ] API works through frontend Nginx
[ ] Logs checked
[ ] Rollback understood
[ ] Cleanup plan understood
```

## What To Do Next

Move to:

```text
Phase 4: Docker Compose
```

Why:

Phase 3 teaches Docker manually. Phase 4 teaches how to define the same multi-container app in one Compose file so students do not need to type many long `docker run` commands every time.
