# Phase 4: Docker Compose Full Stack

## Fresh Start Assumption

This phase starts from a clean Ubuntu EC2 server.

You do not need to complete any previous phase before using this guide.

This guide assumes:

- You have a fresh AWS EC2 server.
- Docker and Docker Compose are not installed yet.
- The repository is not cloned yet.
- You will create files with `vim`.
- You will type commands manually.
- You will not use shell scripts.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What You Will Deploy

This phase deploys the full N-tier application with Docker Compose:

- PostgreSQL database container.
- One-time Alembic migration container.
- FastAPI backend container.
- React/Vite frontend served by Nginx container.
- Private Docker bridge network.
- Named Docker volume for PostgreSQL data.

Architecture:

```text
Browser
  |
  | HTTP port 80
  v
launchboard-frontend
  |
  | /api, /health, /ready
  v
launchboard-backend
  |
  | DATABASE_URL
  v
launchboard-db
```

## When To Use This Architecture

Use Docker Compose when:

- You want to run a complete multi-container app on one server.
- You want one file to describe the app stack.
- You want simpler commands than many separate `docker run` commands.
- You are deploying a small production-style app, student lab, internal tool, or demo.
- You want students to understand services, networks, volumes, health checks, and startup order.

Do not use Docker Compose when:

- You need automatic multi-server scaling.
- You need Kubernetes-style orchestration.
- You need managed cloud databases and load balancers from the start.
- You need high availability across multiple machines.

Why this phase matters:

Phase 3 teaches individual Docker commands. Phase 4 shows how teams normally organize the same containers in a single Compose file. This is easier to read, easier to repeat, and easier to troubleshoot.

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-4` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.micro` or `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-4-sg` |
| SSH Port | `22`, your IP only |
| HTTP Port | `80`, anywhere |
| HTTPS Port | `443`, anywhere if using SSL |

Do not open:

```text
8000
5432
```

The backend and database should stay private inside the Docker Compose network.

## Files Included In This Phase

```text
deployment/phase-4-docker-compose/
+-- .env.example
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- docker-compose.yml
+-- docker-compose.prod.yml
+-- nginx-frontend.conf
+-- README.md
```

The README shows all file contents inline so students can create every file from GitHub without needing to copy hidden files from another branch.

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-4` |
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

Docker Compose still needs a server. EC2 gives us the Linux machine where Docker Engine runs the containers.

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

SSH lets you control the server from your terminal.

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

The server needs basic tools before we clone the repository, install Docker, edit files, and test HTTP endpoints.

Command explanation:

- `apt update` refreshes package metadata.
- `apt upgrade -y` applies available updates.
- `git` clones the repository.
- `curl` tests URLs.
- `vim` creates and edits files.
- `jq` formats JSON output.
- `ca-certificates` and `gnupg` help verify secure package repositories.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/package-management

## Step 4: Install Docker Engine And Compose Plugin

Run:

```bash
cd ~
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${UBUNTU_CODENAME:-$VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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
docker compose version
docker info
```

Why this step exists:

Docker Engine runs containers. Docker Compose reads `docker-compose.yml` and starts the full stack with one command.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/
- Docker Compose docs: https://docs.docker.com/compose/

## Step 5: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-4-ec2" -f ~/.ssh/devops_launchboard_github_key
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
| Title | `devops-launchboard-phase-4-ec2` |
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

GitHub must trust the EC2 public key before the server can clone the repository by SSH.

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

Docker Compose builds the backend and frontend images from the project source code.

Reference:

- Git clone documentation: https://git-scm.com/docs/git-clone

## Step 7: Create Phase 4 Working Files

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-4-docker-compose
```

Why this folder exists:

It keeps the Docker Compose deployment files in one clear place. Students can open this folder and see every file used by Phase 4.

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

Docker sends the build context to the Docker daemon. Without `.dockerignore`, Docker may send local virtual environments, frontend dependencies, build output, caches, and secret env files. That makes builds slower and can accidentally place sensitive files inside images.

Reference:

- Docker build context: https://docs.docker.com/build/concepts/context/

## Step 9: Create Backend Dockerfile

Run:

```bash
vim deployment/phase-4-docker-compose/Dockerfile.backend
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

- The `builder` stage installs dependencies.
- The `runtime` stage runs the app with only what it needs.
- The virtual environment lives in `/opt/venv`.
- The app runs as the non-root `app` user.
- `HEALTHCHECK` lets Docker and Compose know whether the backend is alive.
- `CMD` starts the FastAPI app with Uvicorn.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- FastAPI deployment: https://fastapi.tiangolo.com/deployment/

## Step 10: Create Frontend Dockerfile

Run:

```bash
vim deployment/phase-4-docker-compose/Dockerfile.frontend
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

COPY deployment/phase-4-docker-compose/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Explanation:

- The Node stage builds the Vite frontend.
- The Nginx stage serves the built static files.
- Nginx listens on port `8080` inside the container so it can run as a non-root user.
- EC2 still exposes normal public port `80` through Compose.

Reference:

- Vite build docs: https://vite.dev/guide/build
- Nginx docs: https://nginx.org/en/docs/

## Step 11: Create Nginx Config

Run:

```bash
vim deployment/phase-4-docker-compose/nginx-frontend.conf
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

- `/` serves the frontend.
- `/api/` forwards API traffic to the backend container.
- `/health` and `/ready` forward backend checks through the same public frontend container.
- `launchboard-backend` is the Compose service name. Docker DNS resolves it inside the Compose network.
- `try_files` makes frontend browser routes work after refresh.

Reference:

- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html

## Step 12: Create Compose Environment File

Run:

```bash
vim deployment/phase-4-docker-compose/.env.example
```

Paste:

```env
PROJECT_NAME=devops-launchboard
POSTGRES_DB=launchboard
POSTGRES_USER=launchboard_user
POSTGRES_PASSWORD=CHANGE_ME_STRONG_PASSWORD
DATABASE_URL=postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@launchboard-db:5432/launchboard
APP_NAME=DevOps LaunchBoard API
APP_ENV=production
CORS_ORIGINS=http://YOUR_EC2_PUBLIC_IP
SEED_DEMO_DATA=true
VITE_API_URL=
BACKEND_IMAGE=launchboard-backend:phase-4
FRONTEND_IMAGE=launchboard-frontend:phase-4
```

Create the real `.env` file:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
cp .env.example .env
vim .env
```

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
YOUR_EC2_PUBLIC_IP
```

Why this file exists:

Compose reads `.env` for two things. First, it fills placeholders like `${BACKEND_IMAGE}` in `docker-compose.yml`. Second, services use the same file through `env_file: .env`, so backend and PostgreSQL receive their runtime values without hardcoding secrets in the YAML.

Line explanation:

- `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` initialize PostgreSQL.
- `DATABASE_URL` tells the backend how to connect to PostgreSQL by Compose service name.
- `CORS_ORIGINS` allows the public browser origin.
- `VITE_API_URL=` stays empty so the frontend uses same-origin API calls like `/api/summary`.
- `BACKEND_IMAGE` and `FRONTEND_IMAGE` name the built images.

Reference:

- Compose environment variables: https://docs.docker.com/compose/how-tos/environment-variables/

## Step 13: Create Docker Compose File

Run:

```bash
cd /opt/devops-launchboard/app-source
vim deployment/phase-4-docker-compose/docker-compose.yml
```

Paste:

```yaml
services:
  launchboard-db:
    image: postgres:16-alpine
    container_name: launchboard-db
    env_file:
      - .env
    volumes:
      - launchboard-postgres-data:/var/lib/postgresql/data
    networks:
      - launchboard
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    restart: unless-stopped

  launchboard-migrate:
    build:
      context: ../..
      dockerfile: deployment/phase-4-docker-compose/Dockerfile.backend
    image: ${BACKEND_IMAGE}
    container_name: launchboard-migrate
    env_file:
      - .env
    command: ["alembic", "upgrade", "head"]
    depends_on:
      launchboard-db:
        condition: service_healthy
    networks:
      - launchboard
    restart: "no"

  launchboard-backend:
    build:
      context: ../..
      dockerfile: deployment/phase-4-docker-compose/Dockerfile.backend
    image: ${BACKEND_IMAGE}
    container_name: launchboard-backend
    env_file:
      - .env
    depends_on:
      launchboard-db:
        condition: service_healthy
      launchboard-migrate:
        condition: service_completed_successfully
    networks:
      - launchboard
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 20s
    restart: unless-stopped

  launchboard-frontend:
    build:
      context: ../..
      dockerfile: deployment/phase-4-docker-compose/Dockerfile.frontend
      args:
        VITE_API_URL: ${VITE_API_URL}
    image: ${FRONTEND_IMAGE}
    container_name: launchboard-frontend
    ports:
      - "80:8080"
    depends_on:
      launchboard-backend:
        condition: service_healthy
    networks:
      - launchboard
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:8080/healthz"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped

networks:
  launchboard:
    driver: bridge

volumes:
  launchboard-postgres-data:
```

Explanation:

- `launchboard-db` runs PostgreSQL and stores data in a named volume.
- `launchboard-migrate` runs Alembic once and exits.
- `launchboard-backend` runs FastAPI after the database is healthy and migrations complete.
- `launchboard-frontend` serves the frontend and proxies API traffic to the backend.
- `env_file: .env` keeps real runtime values outside the Compose file.
- The backend has no public `ports` entry, so it is private inside the Compose network.
- `ports: "80:8080"` exposes the frontend container on normal HTTP port `80`.
- `depends_on` with health conditions gives a clearer startup order.
- `networks` creates a private bridge network for service-to-service communication.
- `volumes` creates persistent PostgreSQL storage.

Reference:

- Compose file reference: https://docs.docker.com/reference/compose-file/

## Step 14: Create Production Override File

Run:

```bash
vim deployment/phase-4-docker-compose/docker-compose.prod.yml
```

Paste:

```yaml
services:
  launchboard-db:
    cpus: "1.0"
    mem_limit: 1g

  launchboard-backend:
    cpus: "1.0"
    mem_limit: 512m

  launchboard-frontend:
    cpus: "0.5"
    mem_limit: 256m
```

Explanation:

This file adds basic CPU and memory limits. Limits are useful because one busy container should not consume the entire server. For a small student server, these values are intentionally modest.

Reference:

- Compose resource constraints: https://docs.docker.com/reference/compose-file/services/

## Step 15: Validate Compose Config

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml config
```

Why this step exists:

`docker compose config` checks the YAML and shows the final merged configuration. We include both files because `docker-compose.prod.yml` adds the production-style resource limits.

## Step 16: Build Images

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
```

Verify:

```bash
docker images | grep launchboard
```

Why this step exists:

Compose builds the backend and frontend images from the Dockerfiles. This is the Compose version of manually running `docker build`.

## Step 17: Start The Full Stack

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Verify:

```bash
docker compose ps
```

Expected:

```text
launchboard-db          healthy
launchboard-migrate     exited
launchboard-backend     healthy
launchboard-frontend    healthy
```

Why this step exists:

`docker compose up -d` creates the network, creates the volume, starts PostgreSQL, runs migrations, starts the backend, and starts the frontend.

## Step 18: Verify The Application

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
No CORS error appears in the browser console.
```

## Logs And Debugging

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose ps
docker compose logs launchboard-db
docker compose logs launchboard-migrate
docker compose logs launchboard-backend
docker compose logs launchboard-frontend
```

Follow live logs:

```bash
docker compose logs -f
```

Restart one service:

```bash
docker compose restart launchboard-backend
```

Why this section exists:

Compose groups container logs by service name. That makes it easier for students to find whether the database, migration, backend, or frontend is failing.

## Rollback Plan

Stop the running app:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose down
```

Restore a previous Git version:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
```

Rebuild and start:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
docker compose ps
```

Why rollback exists:

Every production deployment needs a recovery path. If the latest version breaks the app, rollback lets you return to a known commit and rebuild.

## Cleanup

Stop and remove containers while keeping database data:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-4-docker-compose
docker compose down
```

Stop and remove containers plus PostgreSQL data:

```bash
docker compose down -v
```

Remove images:

```bash
docker rmi launchboard-backend:phase-4 launchboard-frontend:phase-4 || true
```

AWS cleanup:

- Terminate the EC2 instance.
- Delete unused EBS volumes.
- Release unused Elastic IPs.
- Check the AWS Billing dashboard.

Reference:

- AWS Billing: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/billing-what-is.html
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html

## Troubleshooting

### Problem 1: Compose File Has An Error

Check:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml config
```

Common causes:

```text
Bad indentation.
Missing .env value.
Wrong Dockerfile path.
```

### Problem 2: Database Is Unhealthy

Check:

```bash
docker compose logs launchboard-db
docker compose exec launchboard-db pg_isready -U launchboard_user -d launchboard
```

Common causes:

```text
Wrong POSTGRES_USER.
Wrong POSTGRES_PASSWORD.
Old volume has different database credentials.
```

Lab fix if you do not need old database data:

```bash
docker compose down -v
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Problem 3: Backend Is Unhealthy

Check:

```bash
docker compose logs launchboard-backend
docker compose logs launchboard-migrate
```

Common causes:

```text
DATABASE_URL password does not match POSTGRES_PASSWORD.
Migrations failed.
Backend image failed to build.
```

### Problem 4: Frontend Loads But API Fails

Check:

```bash
curl -s http://127.0.0.1/api/summary | jq
docker compose logs launchboard-frontend
docker compose logs launchboard-backend
```

Common causes:

```text
Nginx proxy path is wrong.
Backend container is unhealthy.
CORS_ORIGINS does not match public browser URL.
```

## Security Notes

- Do not expose PostgreSQL port `5432` publicly.
- Do not expose backend port `8000` publicly in this phase.
- Store real values in `.env`, not inside `docker-compose.yml`.
- Do not commit `.env`.
- Use strong database passwords.
- Restrict SSH to your IP.
- Use HTTPS for real public deployments.
- Use managed PostgreSQL for serious production systems.

## Production Checklist

```text
[ ] EC2 security group exposes only 22, 80, and optionally 443
[ ] Docker Engine installed
[ ] Docker Compose plugin installed
[ ] GitHub SSH key created and tested
[ ] Repository cloned with SSH
[ ] Root .dockerignore created
[ ] Phase 4 Dockerfiles created
[ ] Nginx frontend config created
[ ] .env.example created
[ ] Real .env created and secrets changed
[ ] docker-compose.yml created
[ ] docker-compose.prod.yml created
[ ] docker compose config passes with production override
[ ] docker compose build succeeds with production override
[ ] docker compose up -d succeeds with production override
[ ] PostgreSQL service healthy
[ ] Migration service completed
[ ] Backend service healthy
[ ] Frontend service healthy
[ ] Public browser URL works
[ ] API works through /api
[ ] Logs checked
[ ] Rollback plan understood
[ ] Cleanup plan understood
```

## Reference Documentation

| Topic | Link |
| --- | --- |
| Docker Engine | https://docs.docker.com/engine/ |
| Docker Compose | https://docs.docker.com/compose/ |
| Compose file reference | https://docs.docker.com/reference/compose-file/ |
| Dockerfile reference | https://docs.docker.com/reference/dockerfile/ |
| Docker volumes | https://docs.docker.com/engine/storage/volumes/ |
| Docker networks | https://docs.docker.com/engine/network/ |
| PostgreSQL Docker image | https://hub.docker.com/_/postgres |
| FastAPI deployment | https://fastapi.tiangolo.com/deployment/ |
| Vite production build | https://vite.dev/guide/build |
| Nginx proxy docs | https://nginx.org/en/docs/http/ngx_http_proxy_module.html |

## What To Do Next

Move to:

```text
Phase 5: Docker Swarm
```

Why:

Docker Compose is excellent for one server. Docker Swarm introduces multi-node orchestration ideas such as services, replicas, stacks, and manager/worker nodes.
