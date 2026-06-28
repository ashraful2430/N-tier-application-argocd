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

## Review Notes Before You Start

I checked the original Phase 4 file and updated the parts that could cause student issues.

| Area | Status | What Was Changed |
| --- | --- | --- |
| Backend Docker image | Production-style and lightweight enough for this phase | Kept Python slim, multi-stage build, non-root runtime user, health check, and no public port. |
| Frontend Docker image | Needed a fix | Removed custom non-root Nginx runtime user because it can cause Nginx PID and entrypoint permission issues. The final image still uses lightweight `nginx:1.27-alpine`. |
| Compose startup order | Good | Kept DB health check, one-time migration service, backend health check, and frontend dependency on backend health. |
| Resource limits | Improved | Reduced limits so the stack is safer for small EC2 lab servers. |
| Security group guidance | Good | Only public ports should be `22`, `80`, and optionally `443`. Backend and database stay private. |

## Is This Production Grade?

For a student lab and small single-server production-style deployment, this is good.

It includes:

- Multi-container separation.
- Docker Compose service definitions.
- Private bridge network.
- Persistent PostgreSQL volume.
- Health checks.
- Restart policies.
- Non-root backend container.
- Lightweight base images.
- No public database port.
- No public backend port.
- Environment-based configuration.
- One-time migration container.

For real company production, you would also add:

- HTTPS with a real domain.
- Managed PostgreSQL or automated backups.
- Centralized logs.
- Metrics and alerts.
- CI/CD image build and deploy flow.
- Image vulnerability scanning.
- Secrets manager instead of plain `.env`.
- A rollback strategy using versioned image tags.

## Image Weight Review

| Image | Base | Lightweight? | Notes |
| --- | --- | --- | --- |
| Backend | `python:3.12-slim` | Yes | Good balance for FastAPI. Multi-stage build avoids keeping build context clutter. |
| Frontend builder | `node:22-alpine` | Yes | Used only to build static files. |
| Frontend runtime | `nginx:1.27-alpine` | Yes | Very lightweight runtime for static frontend files. |
| Database | `postgres:16-alpine` | Yes for labs | Good for this phase. For serious production, use managed PostgreSQL or carefully manage backups. |

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

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| EC2 Name | `devops-launchboard-phase-4` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` recommended, `t3.micro` possible but tight |
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
deployment/phase-04-docker-compose/
├── .env.example
├── Dockerfile.backend
├── Dockerfile.frontend
├── docker-compose.yml
├── docker-compose.prod.yml
├── nginx-frontend.conf
└── README.md
```

Also create this file at the repository root:

```text
.dockerignore
```

## Step 1: Create EC2 Server

Run this step from the AWS Console.

Create one EC2 instance:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-4` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.small` recommended |
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

## Step 2: SSH Into EC2

Run from your local machine:

```bash
chmod 400 devops-launchboard-key.pem
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Command explanation:

| Command Part | Meaning |
| --- | --- |
| `chmod 400 devops-launchboard-key.pem` | Makes the private key readable only by you. SSH rejects keys with open permissions. |
| `ssh` | Opens a secure shell connection to the EC2 server. |
| `-i devops-launchboard-key.pem` | Tells SSH which private key to use. |
| `ubuntu@YOUR_EC2_PUBLIC_IP` | Logs in as the Ubuntu default user on your EC2 public IP. |

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

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `cd ~` | Moves to the Ubuntu user's home directory. |
| `sudo apt update` | Refreshes Ubuntu package metadata. |
| `sudo apt upgrade -y` | Installs available package updates without asking for confirmation. |
| `sudo apt install -y ...` | Installs common tools needed for cloning, editing, downloading, and testing. |

Tool explanation:

| Tool | Why We Install It |
| --- | --- |
| `git` | Clones the GitHub repository. |
| `curl` | Tests HTTP endpoints from the terminal. |
| `wget` | Used by the frontend health check and useful for downloads. |
| `vim` | Edits files directly on EC2. |
| `unzip` | Extracts zip files if needed. |
| `jq` | Formats JSON API responses. |
| `ca-certificates` | Helps verify HTTPS certificates. |
| `gnupg` | Verifies Docker's package signing key. |
| `lsb-release` | Helps identify Ubuntu release information. |

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

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `cd ~` | Moves to the home directory before starting installation. |
| `sudo install -m 0755 -d /etc/apt/keyrings` | Creates Docker's apt keyring directory with safe permissions. |
| `curl -fsSL ... | sudo gpg --dearmor ...` | Downloads Docker's GPG key and saves it in apt-compatible format. |
| `sudo chmod a+r /etc/apt/keyrings/docker.gpg` | Allows apt to read the Docker repository key. |
| `echo "deb ..."` | Adds Docker's official Ubuntu package repository. |
| `sudo apt update` | Refreshes package metadata after adding Docker's repository. |
| `sudo apt install -y ...` | Installs Docker Engine, Docker CLI, Buildx, and Compose plugin. |
| `sudo systemctl enable docker` | Starts Docker automatically after server reboot. |
| `sudo systemctl start docker` | Starts Docker immediately. |
| `sudo usermod -aG docker ubuntu` | Allows the `ubuntu` user to run Docker commands without `sudo` after re-login. |

Log out and SSH back in:

```bash
exit
ssh -i devops-launchboard-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Why:

Group changes from `usermod` apply only after a new login session.

Verify:

```bash
docker --version
docker compose version
docker info
```

Expected:

```text
Docker version ...
Docker Compose version ...
```

Reference:

- Install Docker Engine on Ubuntu: https://docs.docker.com/engine/install/ubuntu/

## Step 5: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-4-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `cd ~` | Moves to the Ubuntu user's home directory. |
| `mkdir -p ~/.ssh` | Creates the SSH folder if it does not already exist. |
| `chmod 700 ~/.ssh` | Allows only the owner to access the SSH folder. |
| `ssh-keygen -t ed25519 ...` | Creates a new SSH key pair for this EC2 server. |
| `cat ~/.ssh/devops_launchboard_github_key.pub` | Prints the public key so you can add it to GitHub. |

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

Config explanation:

| Line | Explanation |
| --- | --- |
| `Host github.com` | Applies this config when connecting to GitHub. |
| `HostName github.com` | Actual hostname to connect to. |
| `User git` | GitHub SSH uses the `git` user. |
| `IdentityFile ...` | Uses the EC2-specific deploy key. |
| `IdentitiesOnly yes` | Forces SSH to use only this key for GitHub. |

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

Expected:

```text
Hi ... You've successfully authenticated...
```

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

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `sudo mkdir -p /opt/devops-launchboard` | Creates the deployment directory under `/opt`. |
| `sudo chmod 755 /opt/devops-launchboard` | Allows normal directory access while keeping safe ownership behavior. |
| `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard` | Lets the Ubuntu user manage files inside this directory. |
| `cd /opt/devops-launchboard` | Moves into the deployment parent directory. |
| `git clone ... app-source` | Clones the project into a folder named `app-source`. |
| `cd app-source` | Moves into the project source directory. |
| `git branch --show-current` | Shows the current Git branch. |

Expected:

```text
main
```

## Step 7: Create Phase 4 Working Folder

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-04-docker-compose
```

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `cd /opt/devops-launchboard/app-source` | Moves to the root of the cloned repository. |
| `mkdir -p deployment/phase-04-docker-compose` | Creates the Phase 4 folder and parent folders if needed. |

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
deployment/phase-04-docker-compose/.env

```

Why this file exists:

Docker sends the build context to the Docker daemon. Without `.dockerignore`, Docker may send local virtual environments, frontend dependencies, build output, caches, and secret env files. That makes builds slower and can accidentally place sensitive files inside images.

Important:

This file must be placed at the repository root:

```text
/opt/devops-launchboard/app-source/.dockerignore
```

## Step 9: Create Backend Dockerfile

Run:

```bash
vim deployment/phase-04-docker-compose/Dockerfile.backend
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

RUN pip install --no-cache-dir --upgrade pip     && pip install --no-cache-dir ".[dev]"

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
ENV APP_ENV=production

RUN groupadd --system app     && useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app /app

RUN chown -R app:app /app /opt/venv

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3).read()" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]

```

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `FROM python:3.12-slim AS builder` | Uses a small Python image for installing dependencies. |
| `ENV PYTHONDONTWRITEBYTECODE=1` | Stops Python from writing `.pyc` files. |
| `ENV PYTHONUNBUFFERED=1` | Sends logs directly to Docker logs without buffering. |
| `ENV VIRTUAL_ENV=/opt/venv` | Defines where the Python virtual environment lives. |
| `ENV PATH="/opt/venv/bin:${PATH}"` | Makes commands use the virtual environment first. |
| `WORKDIR /app` | Sets `/app` as the working directory. |
| `RUN python -m venv /opt/venv` | Creates an isolated Python environment. |
| `COPY backend/pyproject.toml backend/alembic.ini ./` | Copies backend package and Alembic config. |
| `COPY backend/app ./app` | Copies the FastAPI application code. |
| `COPY backend/alembic ./alembic` | Copies migration files. |
| `RUN pip install ... ".[dev]"` | Installs Python dependencies, including Alembic for migrations. |
| `FROM python:3.12-slim AS runtime` | Starts a clean runtime image. |
| `ENV APP_ENV=production` | Sets the default runtime environment to production. |
| `RUN groupadd ... useradd ...` | Creates a non-root Linux user for the backend. |
| `COPY --from=builder /opt/venv /opt/venv` | Copies installed dependencies from builder stage. |
| `COPY --from=builder /app /app` | Copies app files from builder stage. |
| `RUN chown -R app:app ...` | Gives the non-root user access to app files. |
| `USER app` | Runs the backend as a non-root user. |
| `EXPOSE 8000` | Documents that the backend listens on container port `8000`. |
| `HEALTHCHECK ... /health` | Lets Docker check whether the backend is alive. |
| `CMD ["uvicorn", ...]` | Starts the FastAPI app with Uvicorn. |

Production-grade note:

This backend image is production-style for this phase because it uses a slim base image, multi-stage build, non-root user, health check, and no public port mapping in Compose.

Reference:

- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- Multi-stage builds: https://docs.docker.com/build/building/multi-stage/

## Step 10: Create Frontend Dockerfile

Run:

```bash
vim deployment/phase-04-docker-compose/Dockerfile.frontend
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

COPY deployment/phase-04-docker-compose/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]

```

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `FROM node:22-alpine AS builder` | Uses a lightweight Node image only for building the frontend. |
| `WORKDIR /app` | Sets the working directory inside the builder container. |
| `ARG VITE_API_URL=""` | Defines a build argument for the frontend API URL. |
| `ENV VITE_API_URL=${VITE_API_URL}` | Makes the build argument available during Vite build. |
| `COPY frontend/package*.json ./` | Copies dependency files first for better Docker layer caching. |
| `RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi` | Uses `npm ci` when lock file exists, otherwise falls back to `npm install`. |
| `COPY frontend/ ./` | Copies the frontend source code. |
| `RUN npm run build` | Builds the production static frontend files. |
| `FROM nginx:1.27-alpine AS runtime` | Uses a lightweight Nginx image to serve the built frontend. |
| `COPY ... default.conf` | Copies the Nginx site config into the container. |
| `COPY --from=builder /app/dist ...` | Copies only built static files into the runtime image. |
| `EXPOSE 8080` | Documents that Nginx listens on container port `8080`. |
| `HEALTHCHECK ... /healthz` | Checks whether the frontend Nginx container is responding. |
| `CMD ["nginx", "-g", "daemon off;"]` | Starts Nginx in the foreground so Docker can manage the process. |

Production-grade note:

The frontend image is lightweight because the final runtime image contains only Nginx and static build files. It does not contain `node_modules` or the Node build tools.

Important fix:

This version does not force a custom non-root Nginx user. The official Nginx Alpine image already has its expected entrypoint and runtime paths. This avoids the permission and PID problems students faced in Phase 3.

Reference:

- Official Nginx Docker image: https://hub.docker.com/_/nginx
- Vite environment variables: https://vite.dev/guide/env-and-mode

## Step 11: Create Nginx Config

Run:

```bash
vim deployment/phase-04-docker-compose/nginx-frontend.conf
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

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `server {` | Starts one Nginx virtual server block. |
| `listen 8080;` | Makes Nginx listen on container port `8080`. |
| `server_name _;` | Matches any hostname. |
| `root /usr/share/nginx/html;` | Points Nginx to the built frontend files. |
| `index index.html;` | Uses `index.html` as the default page. |
| `client_max_body_size 10M;` | Allows requests up to 10 MB. |
| `location = /healthz` | Provides a simple frontend container health endpoint. |
| `access_log off;` | Disables access logs for the health check endpoint. |
| `return 200 "ok";` | Returns a simple successful health response. |
| `location /api/` | Matches API requests from the browser. |
| `proxy_pass http://launchboard-backend:8000/api/;` | Sends API traffic to the backend Compose service. |
| `proxy_http_version 1.1;` | Uses HTTP/1.1 for proxying. |
| `proxy_set_header Host $host;` | Preserves the original host header. |
| `proxy_set_header X-Real-IP $remote_addr;` | Sends the client IP to the backend. |
| `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` | Maintains proxy forwarding chain information. |
| `proxy_set_header X-Forwarded-Proto $scheme;` | Tells backend whether request used HTTP or HTTPS. |
| `location = /health` | Proxies backend health checks. |
| `location = /ready` | Proxies backend readiness checks. |
| `location /` | Handles all frontend routes. |
| `try_files $uri $uri/ /index.html;` | Supports React browser refresh and client-side routing. |

Reference:

- Nginx server block documentation: https://nginx.org/en/docs/http/ngx_http_core_module.html
- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html

## Step 12: Create Compose Environment File

Run:

```bash
vim deployment/phase-04-docker-compose/.env.example
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
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
cp .env.example .env
vim .env
```

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
YOUR_EC2_PUBLIC_IP
```

Line-by-line explanation:

| Variable | Explanation |
| --- | --- |
| `PROJECT_NAME` | Human-readable project name. |
| `POSTGRES_DB` | Database name created by PostgreSQL. |
| `POSTGRES_USER` | Database user created by PostgreSQL. |
| `POSTGRES_PASSWORD` | Database password. Change this. |
| `DATABASE_URL` | Backend database connection string using Compose service DNS name `launchboard-db`. |
| `APP_NAME` | Backend application name. |
| `APP_ENV` | Backend runtime environment. |
| `CORS_ORIGINS` | Public browser origin allowed by the backend. |
| `SEED_DEMO_DATA` | Allows demo data to be created when needed. |
| `VITE_API_URL` | Empty value means frontend uses same-origin routes like `/api/summary`. |
| `BACKEND_IMAGE` | Name and tag for the backend image built by Compose. |
| `FRONTEND_IMAGE` | Name and tag for the frontend image built by Compose. |

Important:

The password in `DATABASE_URL` must match `POSTGRES_PASSWORD`.

## Step 13: Create Docker Compose File

Run:

```bash
cd /opt/devops-launchboard/app-source
vim deployment/phase-04-docker-compose/docker-compose.yml
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
      dockerfile: deployment/phase-04-docker-compose/Dockerfile.backend
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
      dockerfile: deployment/phase-04-docker-compose/Dockerfile.backend
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
      dockerfile: deployment/phase-04-docker-compose/Dockerfile.frontend
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

Service explanation:

| Service | Purpose |
| --- | --- |
| `launchboard-db` | Runs PostgreSQL. |
| `launchboard-migrate` | Runs Alembic migrations once and exits. |
| `launchboard-backend` | Runs the FastAPI backend. |
| `launchboard-frontend` | Runs Nginx and serves the frontend publicly. |

Important Compose line explanation:

| Compose Line | Explanation |
| --- | --- |
| `image: postgres:16-alpine` | Uses the official lightweight PostgreSQL image. |
| `env_file: .env` | Loads runtime variables from `.env`. |
| `volumes: launchboard-postgres-data:/var/lib/postgresql/data` | Keeps database data after container restart. |
| `networks: launchboard` | Places services on the same private Docker network. |
| `healthcheck` | Tells Compose whether a service is healthy. |
| `depends_on: condition: service_healthy` | Waits for a dependency to become healthy before starting the next service. |
| `condition: service_completed_successfully` | Starts backend only after migration finishes successfully. |
| `ports: "80:8080"` | Publishes frontend to EC2 public port `80`. |
| No backend `ports` | Keeps backend private inside the Compose network. |
| No database `ports` | Keeps PostgreSQL private inside the Compose network. |

Reference:

- Compose file reference: https://docs.docker.com/reference/compose-file/
- Compose healthcheck and depends_on: https://docs.docker.com/compose/how-tos/startup-order/

## Step 14: Create Production Override File

Run:

```bash
vim deployment/phase-04-docker-compose/docker-compose.prod.yml
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

Line-by-line explanation:

| Line | Explanation |
| --- | --- |
| `services:` | Starts service override definitions. |
| `launchboard-db:` | Adds resource limits for PostgreSQL. |
| `cpus: "1.0"` | Allows up to one full CPU core. |
| `mem_limit: 1g` | Limits PostgreSQL memory usage to 1 GB. |
| `launchboard-backend:` | Adds resource limits for backend. |
| `mem_limit: 512m` | Keeps backend memory controlled on small servers. |
| `launchboard-frontend:` | Adds resource limits for frontend. |
| `mem_limit: 256m` | Nginx static frontend does not need much memory. |

Note:

These limits are lab-friendly. On a real production server, tune CPU and memory based on metrics.

Reference:

- Compose merge and override: https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/
- Compose resource constraints: https://docs.docker.com/reference/compose-file/deploy/#resources

## Step 15: Validate Compose Config

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml config
```

Command explanation:

| Part | Explanation |
| --- | --- |
| `docker compose` | Runs the Compose plugin. |
| `-f docker-compose.yml` | Loads the main Compose file. |
| `-f docker-compose.prod.yml` | Applies the production override file. |
| `config` | Validates and prints the final merged configuration. |

## Step 16: Build Images

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
```

Verify:

```bash
docker images | grep launchboard
```

Command explanation:

| Command | Explanation |
| --- | --- |
| `docker compose ... build` | Builds backend and frontend images using the Dockerfiles. |
| `docker images` | Lists local Docker images. |
| `grep launchboard` | Filters only images with `launchboard` in the name. |

## Step 17: Start The Full Stack

Run:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

Verify:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

Command explanation:

| Command | Explanation |
| --- | --- |
| `docker compose ... up -d` | Creates the network, volume, containers, and starts the full app in detached mode. |
| `docker compose ... ps` | Shows status and health of Compose services. |

Expected:

```text
launchboard-db          healthy
launchboard-migrate     exited
launchboard-backend     healthy
launchboard-frontend    healthy
```

## Step 18: Verify The Application

Run from EC2:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Command explanation:

| Command | Explanation |
| --- | --- |
| `curl -I http://127.0.0.1` | Checks whether the frontend returns HTTP headers. |
| `curl -s http://127.0.0.1/health \| jq` | Checks backend health through the frontend proxy. |
| `curl -s http://127.0.0.1/ready \| jq` | Checks backend readiness through the frontend proxy. |
| `curl -s http://127.0.0.1/api/summary \| jq` | Checks a real API route through Nginx. |

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
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-db
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-migrate
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-backend
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-frontend
```

Follow live logs:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f
```

Restart one service:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart launchboard-backend
```

Tool explanation:

| Tool | Meaning |
| --- | --- |
| `docker compose ps` | Shows service status. |
| `docker compose logs SERVICE_NAME` | Shows logs for one service. |
| `docker compose logs -f` | Streams live logs from all services. |
| `docker compose restart SERVICE_NAME` | Restarts one service without recreating the full stack. |

## Rollback Plan

Stop the running app:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
```

Restore a previous Git version:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
```

Rebuild and start:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml build
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
```

## Cleanup

Stop and remove containers while keeping database data:

```bash
cd /opt/devops-launchboard/app-source/deployment/phase-04-docker-compose
docker compose -f docker-compose.yml -f docker-compose.prod.yml down
```

Stop and remove containers plus PostgreSQL data:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml down -v
```

Remove images:

```bash
docker rmi launchboard-backend:phase-4 launchboard-frontend:phase-4 || true
```

Full Docker lab cleanup:

```bash
docker system prune -a --volumes
```

Warning:

`docker compose down -v` deletes the PostgreSQL volume for this app. `docker system prune -a --volumes` removes unused containers, networks, images, build cache, and volumes from the whole Docker host.

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
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-db
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec launchboard-db pg_isready -U launchboard_user -d launchboard
```

Common causes:

```text
Wrong POSTGRES_USER.
Wrong POSTGRES_PASSWORD.
Old volume has different database credentials.
```

Lab fix if you do not need old database data:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml down -v
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Problem 3: Migration Failed

Check:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-migrate
```

Common causes:

```text
DATABASE_URL is wrong.
PostgreSQL password does not match DATABASE_URL.
Alembic files are missing from the image.
Application dependencies failed to install.
```

### Problem 4: Backend Is Unhealthy

Check:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-backend
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-migrate
```

Common causes:

```text
DATABASE_URL password does not match POSTGRES_PASSWORD.
Migrations failed.
Backend image failed to build.
Backend /health route is failing.
```

### Problem 5: Frontend Container Is Unhealthy

Check:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-frontend
curl -I http://127.0.0.1
```

Common causes:

```text
Nginx config file path is wrong.
Frontend build did not create /app/dist.
Port 80 is already used by another process.
```

Check port 80:

```bash
sudo ss -tulpn | grep ':80'
```

### Problem 6: Frontend Loads But API Fails

Check:

```bash
curl -s http://127.0.0.1/api/summary | jq
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-frontend
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs launchboard-backend
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

Docker Compose is excellent for one server. Docker Swarm introduces multi-node orchestration ideas such as services, replicas, stacks, and manager/worker nodes.
