# Phase 3: Docker Single Container Deployment

## Fresh Start Assumption

You do not need to complete Phase 1 or Phase 2 before using this guide.

This phase starts from a clean AWS account or clean AWS lab environment and a fresh Ubuntu EC2 server.

This phase deploys the N-tier application manually with Docker commands on one EC2 instance:

- PostgreSQL runs in one Docker container.
- FastAPI backend runs in one Docker container.
- React/Vite frontend is built into a Docker image and served by an Nginx container.
- A Docker network lets the containers talk to each other by container name.
- A Docker volume stores PostgreSQL data outside the PostgreSQL container.

Students read this README from GitHub in the browser. Do not assume the deployment folder already exists on the EC2 server. Every file that must be created is shown inline immediately after the `vim` command that creates it.

No shell scripts are required in this phase.

Project repository:

```text
git@github.com:ashraful2430/N-tier-application.git
```

## What This Phase Teaches

By completing this phase, students will learn:

- How to create an EC2 server for Docker deployment.
- How to SSH into Ubuntu EC2.
- How to install Docker Engine from Docker's official apt repository.
- How Docker images and containers are different.
- How to create Dockerfiles for backend and frontend.
- How to create a Docker network.
- How containers resolve each other by container name.
- How to create a Docker volume for PostgreSQL data.
- How to run PostgreSQL as a container.
- How to run Alembic migrations from a temporary backend container.
- How to run a FastAPI backend as a long-running Docker container.
- How to run a React/Vite frontend inside an Nginx Docker container.
- How to expose only the frontend container publicly.
- How to keep backend and database ports private.
- How to inspect Docker logs, health checks, networks, volumes, and containers.
- How to tag Docker images for Docker Hub.
- How to push backend and frontend images to your own Docker Hub repositories.
- How to stop, remove, rebuild, and rerun containers manually.

## Architecture

```text
User Browser
  |
  | HTTP on EC2 port 80
  v
Frontend Nginx container
  |
  +-- serves frontend static files from /usr/share/nginx/html
  |
  +-- proxies /api, /health, and /ready to backend container
        |
        v
      FastAPI backend container on port 8000
        |
        v
      PostgreSQL container on port 5432
```

Container map:

| Container | Image | Internal Port | Public Access | Purpose |
| --- | --- | ---: | --- | --- |
| `launchboard-frontend` | `launchboard-frontend:phase-3` or `<dockerhub-username>/launchboard-frontend:phase-3` | `8080` | Yes, mapped to EC2 port `80` | Serves frontend and proxies API traffic |
| `launchboard-backend` | `launchboard-backend:phase-3` or `<dockerhub-username>/launchboard-backend:phase-3` | `8000` | No | Runs FastAPI API |
| `launchboard-postgres` | `postgres:16-alpine` | `5432` | No | Stores application data |

Important idea:

Users should reach only the frontend Nginx container through EC2 port `80`. The backend and database should stay private inside the Docker network.

## Architecture Decision Guide

Use Phase 3 when:

- You want students to understand raw Docker commands before Docker Compose.
- You want to teach images, containers, networks, volumes, logs, ports, and health checks.
- You want a manual bridge between bare-metal deployment and Docker Compose.
- You want students to see how each container is started by hand.

Do not use Phase 3 when:

- You want one command to run the full stack.
- You need easier environment management.
- You need multi-server orchestration.
- You need automatic rolling updates.
- You need Kubernetes-style scheduling or service discovery.

Production note:

This is production-style for learning Docker on one server, but not a complete production platform. Real production should also consider Docker Compose or an orchestrator, managed database backups, image registry scanning, CI/CD, monitoring, centralized logs, secrets management, TLS, and automated rollback. This phase now includes Docker Hub push steps so students learn how image registries fit into the deployment flow.

## Cost Warning

This phase can create AWS charges:

| Resource | Cost Risk | Why |
| --- | --- | --- |
| EC2 instance | Medium | Billed while running |
| EBS volume | Medium | Storage attached to EC2 |
| Elastic IP | Medium | Charged if unused or in some public IPv4 cases |
| Data transfer | Low to medium | Depends on traffic |
| Snapshot | Medium | Charged if created |

Cost-safe practice:

- Use one small EC2 instance.
- Do not create a NAT Gateway.
- Do not create a Load Balancer.
- Do not create RDS for this phase.
- Stop or terminate the server after practice.
- Delete unused EBS volumes and snapshots.
- Create an AWS Budget alert.

Reference:

- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- AWS EC2 documentation: https://docs.aws.amazon.com/ec2/

## Recommended AWS Setup

| Item | Recommended Value |
| --- | --- |
| AWS Region | `ap-southeast-1` or closest region |
| EC2 Name | `devops-launchboard-phase-3` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.micro` or `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-3-sg` |
| SSH | Port `22`, your IP only |
| HTTP | Port `80`, anywhere |
| HTTPS | Port `443`, anywhere if using SSL later |
| Backend | Port `8000`, do not expose publicly |
| PostgreSQL | Port `5432`, do not expose publicly |

Security group inbound rules:

| Type | Port | Source | Purpose |
| --- | ---: | --- | --- |
| SSH | `22` | Your IP only | Server access |
| HTTP | `80` | `0.0.0.0/0` | Public frontend container |
| HTTPS | `443` | `0.0.0.0/0` | Public app with SSL later |

Do not open:

```text
8000
5432
5173
```

Why:

- `8000` is private backend container traffic.
- `5432` is private PostgreSQL container traffic.
- `5173` is a Vite development server port and should not be used in production.

## Files Created In This Phase

```text
deployment/phase-3-docker/
+-- env/
|   +-- backend.docker.env.example
|   +-- frontend.build.env.example
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
+-- README.md

Repository root:
+-- .dockerignore
```

Important Docker rule:

The `.dockerignore` file must be in the Docker build context root. In this phase, the build context is the repository root because the build command ends with `.`.

That means this file must exist here:

```text
/opt/devops-launchboard/app-source/.dockerignore
```

If `.dockerignore` is created only inside `deployment/phase-3-docker/`, Docker will not use it for the build context.

## Deployment Plan

You will follow this flow:

1. Create EC2 server.
2. SSH into EC2.
3. Install base tools.
4. Install Docker Engine.
5. Log out and SSH back in so Docker group access works.
6. Create GitHub SSH key on EC2.
7. Clone the project from `main`.
8. Create Docker phase files.
9. Create real backend environment file.
10. Build backend and frontend Docker images.
11. Create Docker Hub repositories, log in, tag images, and push images.
12. Create Docker network and volume.
13. Run PostgreSQL container.
14. Wait for PostgreSQL to be ready.
15. Run Alembic migrations from a temporary backend container.
16. Run backend container.
17. Run frontend container.
18. Verify the app from the EC2 public IP.
19. Debug logs and health checks if needed.
20. Rollback or cleanup.

## Step 1: Create EC2 Server

Run this step from: AWS Console

Create an EC2 instance with:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-3` |
| AMI | Ubuntu Server 24.04 LTS |
| Architecture | 64-bit x86 |
| Instance Type | `t3.micro` or `t3.small` |
| Key Pair | `devops-launchboard-key` |
| Storage | 20 GB gp3 |
| Public IP | Enabled |

Security group inbound rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | `22` | Your IP |
| HTTP | `80` | Anywhere |
| HTTPS | `443` | Anywhere |

Expected result:

```text
EC2 instance state: Running
Status checks: 2/2 checks passed
```

Why this step exists:

Docker containers still need a Linux host. EC2 is the server where Docker Engine runs containers.

Reference:

- Connect to EC2 Linux instance: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html
- EC2 security groups: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html

## Step 2: SSH Into EC2

Run this command from: your local machine where the `.pem` key exists

Replace:

- `<key-file>` with your key file
- `<public-ip>` with your EC2 public IP

```bash
chmod 400 <key-file>.pem
ssh -i <key-file>.pem ubuntu@<public-ip>
```

Command explanation:

- `chmod 400 <key-file>.pem` sets the key file to read-only for your user. SSH refuses to connect if the key file has loose permissions.
- `ssh -i <key-file>.pem ubuntu@<public-ip>` connects to the EC2 server. `-i` tells SSH which key to use. `ubuntu` is the default user on Ubuntu EC2 instances created by AWS.

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

SSH gives you terminal access to install Docker, clone code, build images, run containers, and inspect logs.

## Step 3: Update Server And Install Base Tools

Run this command from: EC2 server

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim jq tree unzip ca-certificates gnupg lsb-release software-properties-common
```

Command explanation:

- `cd ~` moves you to your home directory, `/home/ubuntu`, so you start from a known location.
- `sudo apt update` refreshes the list of available packages from Ubuntu's servers.
- `sudo apt upgrade -y` upgrades installed packages and applies security patches.
- `git` clones the project from GitHub.
- `curl` and `wget` download setup files and test endpoints.
- `vim` edits config files directly on the server.
- `jq` formats JSON output from API and Docker inspection commands.
- `tree` shows folder structures visually.
- `unzip` extracts zip archives.
- `ca-certificates` and `gnupg` allow apt to verify signed package repositories.
- `lsb-release` and `software-properties-common` help with repository setup and OS information.

Verify:

```bash
git --version
curl --version
jq --version
tree --version
```

Why this step exists:

Fresh servers have old package metadata and may be missing tools needed for Docker installation and deployment verification.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/how-to/software/package-management/index.html

## Step 4: Install Docker Engine

Run this command from: EC2 server

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

- `sudo install -m 0755 -d /etc/apt/keyrings` creates the directory where apt stores trusted GPG keys.
- `curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg` downloads Docker's GPG key and saves it in apt's keyring format.
- `sudo chmod a+r /etc/apt/keyrings/docker.gpg` allows apt to read the key.
- `echo "deb ..." | sudo tee /etc/apt/sources.list.d/docker.list` adds Docker's official Ubuntu repository.
- `sudo apt update` refreshes package metadata, including the Docker repository.
- `sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin` installs Docker Engine, Docker CLI, container runtime, and Buildx build support.
- `sudo systemctl enable docker` starts Docker automatically after server reboot.
- `sudo systemctl start docker` starts Docker immediately.
- `sudo usermod -aG docker ubuntu` adds the `ubuntu` user to the `docker` group so students do not need `sudo` before every Docker command.

Important:

Group membership does not update inside your current SSH session. You must log out and SSH back in.

Run:

```bash
exit
ssh -i <key-file>.pem ubuntu@<public-ip>
```

Verify after logging back in:

```bash
whoami
groups
docker --version
docker info --format '{{.ServerVersion}}'
docker run --rm hello-world
```

Expected:

```text
ubuntu
ubuntu adm dialout cdrom floppy sudo audio dip video plugdev netdev lxd docker
```

You should see `docker` in the group list.

Why this step exists:

Docker Engine builds images and runs containers. The Docker daemon runs as a system service. The `docker` group allows the `ubuntu` user to talk to the Docker daemon.

Security note:

Membership in the `docker` group is powerful. A user in this group has near-root control through Docker. This is acceptable for this lab server, but production teams should restrict Docker access carefully.

Reference:

- Docker Engine Ubuntu install: https://docs.docker.com/engine/install/ubuntu/
- Docker post-install steps: https://docs.docker.com/engine/install/linux-postinstall/

## Step 5: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-3-ec2" -f ~/.ssh/devops_launchboard_github_key
cat ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `cd ~` moves you to your home directory before creating SSH files.
- `mkdir -p ~/.ssh` creates the `.ssh` folder if it does not exist.
- `chmod 700 ~/.ssh` allows only your user to read, write, or enter the `.ssh` folder.
- `ssh-keygen -t ed25519 ...` creates a new SSH key pair for GitHub access.
- `-C "devops-launchboard-phase-3-ec2"` adds a label so you can identify this key in GitHub.
- `-f ~/.ssh/devops_launchboard_github_key` saves the key with a custom name and avoids overwriting default keys.
- `cat ~/.ssh/devops_launchboard_github_key.pub` prints the public key so you can copy it into GitHub.

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

Why "Allow write access" stays unchecked:

This EC2 server only needs to clone and pull code. It does not need to push changes back to GitHub. Keeping write access off limits damage if the server is compromised.

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

- `Host github.com` tells SSH this block applies when connecting to GitHub.
- `HostName github.com` is the real host.
- `User git` is the required SSH user for GitHub.
- `IdentityFile ~/.ssh/devops_launchboard_github_key` tells SSH which private key to use.
- `IdentitiesOnly yes` forces SSH to use only this key for GitHub.

Secure permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/devops_launchboard_github_key
chmod 644 ~/.ssh/devops_launchboard_github_key.pub
```

Command explanation:

- `chmod 600 ~/.ssh/config` makes the SSH config readable only by your user.
- `chmod 600 ~/.ssh/devops_launchboard_github_key` locks down the private key.
- `chmod 644 ~/.ssh/devops_launchboard_github_key.pub` keeps the public key readable. Public keys are not secret.

Test:

```bash
ssh -T git@github.com
```

Expected result:

```text
Hi <username>/<repo>! You've successfully authenticated, but GitHub does not provide shell access.
```

If you see this message, SSH works. GitHub does not open a remote shell. That is normal.

Why this step exists:

The EC2 server needs GitHub access to clone the app source code. SSH deploy keys are safer than using personal passwords.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

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
tree -L 2 -a
```

Command explanation:

- `sudo mkdir -p /opt/devops-launchboard` creates the parent deployment folder.
- `sudo chmod 755 /opt/devops-launchboard` allows your `ubuntu` user to enter the folder and prevents the parent-folder permission issue from Phase 2.
- `sudo chown -R ubuntu:ubuntu /opt/devops-launchboard` gives the `ubuntu` user ownership of this lab deployment folder.
- `cd /opt/devops-launchboard` moves into the deployment folder.
- `git clone ... app-source` clones the project into `/opt/devops-launchboard/app-source`.
- `git branch --show-current` prints the current Git branch.
- `tree -L 2 -a` shows the project structure two levels deep.

Expected branch:

```text
main
```

Why this step exists:

The Dockerfiles use the repository root as the build context. Docker needs access to `backend`, `frontend`, and `deployment/phase-3-docker` during image builds.

Reference:

- Git clone docs: https://git-scm.com/docs/git-clone

## Step 7: Create Phase 3 Files With Vim

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-3-docker/env
```

Command explanation:

- `cd /opt/devops-launchboard/app-source` moves to the repository root. This is important because Docker build commands later use this folder as the build context.
- `mkdir -p deployment/phase-3-docker/env` creates the folder for Docker phase files and env examples.

Why this folder exists:

This folder keeps Docker-specific files for Phase 3 in one place. Students can inspect them, compare them with the README, and reuse the idea in Docker Compose later.

### Create Root `.dockerignore`

Run this from the repository root:

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
deployment/phase-3-docker/env/*.env
deployment/phase-4-docker-compose/volumes
```

Command explanation:

- `.dockerignore` tells Docker which files to exclude from the build context.
- This file must be in the repository root because the build command uses `.` as the build context.
- If this file is placed only in `deployment/phase-3-docker/`, Docker will ignore it.

Pattern explanation:

- `.git` and `.github` are not needed inside Docker images.
- `.venv` and `backend/.venv` are local Python virtual environments and should not be copied into Docker images.
- `frontend/node_modules` is rebuilt inside the frontend image.
- `frontend/dist` is generated during the frontend Docker build.
- `node_modules` excludes any accidental root-level Node dependency folder.
- `__pycache__`, `*.pyc`, `.pytest_cache`, and `.ruff_cache` are Python cache and tool cache folders.
- `.env` and `.env.*` prevent common env files from entering the build context.
- `deployment/phase-3-docker/env/*.env` prevents the real Docker env file from entering the build context.
- `deployment/phase-4-docker-compose/volumes` excludes later local volume data if it exists.

Verify:

```bash
ls -la .dockerignore
```

Why this step exists:

Docker sends the build context to the Docker daemon. Excluding secrets, cache folders, and heavy dependency folders keeps builds safer and faster.

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
    && pip install --no-cache-dir ".[dev]"

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

Dockerfile explanation:

- `FROM python:3.12-slim AS builder` starts a build stage using a small Python base image.
- `PYTHONDONTWRITEBYTECODE=1` stops Python from writing `.pyc` files.
- `PYTHONUNBUFFERED=1` makes logs appear immediately in `docker logs`.
- `VIRTUAL_ENV=/opt/venv` and `PATH=...` make the virtual environment the default Python environment.
- `WORKDIR /app` sets the working directory inside the image.
- `RUN python -m venv /opt/venv` creates a virtual environment inside the image.
- `COPY backend/pyproject.toml backend/alembic.ini ./` copies backend package metadata and Alembic config.
- `COPY backend/app ./app` copies FastAPI app code.
- `COPY backend/alembic ./alembic` copies Alembic migration files.
- `pip install --no-cache-dir --upgrade pip` upgrades pip without keeping cache files.
- `pip install --no-cache-dir ".[dev]"` installs the backend package and dev extras. This is needed here because this phase runs `alembic upgrade head` from the backend image, and Alembic is often stored in dev dependencies.
- `FROM python:3.12-slim AS runtime` starts a cleaner runtime image.
- `groupadd` and `useradd` create a non-root user named `app`.
- `COPY --from=builder /opt/venv /opt/venv` copies installed Python dependencies from the builder stage.
- `COPY --from=builder /app /app` copies app code from the builder stage.
- `RUN chown -R app:app /app /opt/venv` gives the app user ownership of runtime files.
- `USER app` runs the backend as a non-root user.
- `EXPOSE 8000` documents the backend port inside the container.
- `HEALTHCHECK` lets Docker check if the backend responds on `/health`.
- `CMD ...` starts Uvicorn and binds it to `0.0.0.0`, which means the process listens on the container network interface.

Why `0.0.0.0` is used inside the backend container:

Inside a container, `127.0.0.1` means only that container itself. Other containers cannot reach it. `0.0.0.0` lets the frontend container reach the backend container through the Docker network.

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
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY frontend/ ./
RUN npm run build

FROM nginx:1.27-alpine AS runtime


COPY deployment/phase-3-docker/nginx-frontend.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

Dockerfile explanation:

- `FROM node:22-alpine AS builder` starts a lightweight Node.js build stage.
- `WORKDIR /app` sets the frontend working directory inside the image.
- `ARG VITE_API_URL=""` defines a build-time variable. Empty means the frontend uses same-origin API paths such as `/api/summary`.
- `ENV VITE_API_URL=${VITE_API_URL}` makes the build argument available during `npm run build`.
- `COPY frontend/package*.json ./` copies dependency files first to improve build caching.
- `RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi` uses `npm ci` when a lock file exists and falls back to `npm install` if the project has no lock file.
- `COPY frontend/ ./` copies the frontend source code.
- `RUN npm run build` creates the production build in `dist`.
- `FROM nginx:1.27-alpine AS runtime` starts a small Nginx runtime image.
- `COPY deployment/phase-3-docker/nginx-frontend.conf ...` replaces Nginx's default site config.
- `COPY --from=builder /app/dist /usr/share/nginx/html` copies built frontend files into Nginx's web root.
- `EXPOSE 8080` documents the internal container port. It does not publish the port by itself. The `docker run -p 80:8080` command publishes it later.
- `HEALTHCHECK` checks the frontend Nginx health endpoint.
- `CMD ["nginx", "-g", "daemon off;"]` starts Nginx in the foreground, which is required for Docker containers.

Why Nginx listens on `8080` inside the container:

The container listens on `8080`, and Docker maps EC2 public port `80` to container port `8080` later. This keeps the app URL clean while making the internal container port explicit.

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

Nginx config explanation:

- `listen 8080` accepts HTTP traffic inside the container on port `8080`.
- `server_name _` is a catch-all value for this container.
- `root /usr/share/nginx/html` points to the built frontend files copied by the Dockerfile.
- `index index.html` tells Nginx which file to serve for directory requests.
- `client_max_body_size 10M` allows request bodies up to 10 MB.
- `location = /healthz` returns `ok` directly from frontend Nginx. It checks whether Nginx is alive.
- `location /api/` forwards API traffic to the backend container.
- `proxy_pass http://launchboard-backend:8000/api/` uses the backend container name as a DNS name. Docker provides this DNS resolution because both containers are attached to `launchboard-net`.
- `location = /health` forwards backend health checks to the backend container.
- `location = /ready` forwards backend readiness checks to the backend container.
- `proxy_set_header Host $host` forwards the original host.
- `proxy_set_header X-Real-IP $remote_addr` forwards the client IP seen by Nginx.
- `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for` forwards the request IP chain.
- `proxy_set_header X-Forwarded-Proto $scheme` forwards `http` or `https` information.
- `location / { try_files $uri $uri/ /index.html; }` supports React/Vite browser routes. If a route does not exist as a real file, Nginx returns `index.html` and the frontend router handles it.

Simple traffic flow:

```text
Browser opens http://YOUR_EC2_PUBLIC_IP
Frontend container serves index.html

Browser calls http://YOUR_EC2_PUBLIC_IP/api/summary
Frontend Nginx container proxies to http://launchboard-backend:8000/api/summary
Backend container returns JSON
Frontend Nginx container returns the response to the browser
```

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

Env explanation:

- `APP_NAME` names the FastAPI app.
- `APP_ENV=production` labels this as a production-style Docker runtime.
- `DATABASE_URL` points to the PostgreSQL container. `launchboard-postgres` is the container name and works as a hostname inside the Docker network.
- `CORS_ORIGINS` should match the public browser origin.
- `SEED_DEMO_DATA=true` loads sample dashboard data if the app supports demo seeding.

Important:

Docker env files are not shell scripts. Do not wrap values in quotes unless you want quotes to become part of the value.

Password safety:

For student labs, use a simple strong password with letters and numbers first. Special characters such as `@`, `/`, `:`, `#`, `?`, and `&` can break a database URL unless they are URL encoded.

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

An empty `VITE_API_URL` makes the frontend call relative URLs. For example, the browser calls `/api/summary`, and the frontend Nginx container proxies that request to the backend container.

Why this is useful:

The browser only needs one public origin:

```text
http://YOUR_EC2_PUBLIC_IP
```

The frontend and backend appear under the same origin, so students avoid CORS issues in this phase.

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

Example:

```env
APP_NAME=DevOps LaunchBoard API
APP_ENV=production
DATABASE_URL=postgresql+asyncpg://launchboard_user:ashik12345@launchboard-postgres:5432/launchboard
CORS_ORIGINS=http://13.229.10.25
SEED_DEMO_DATA=true
```

Command explanation:

- `cp ...example ...env` copies the safe example file into a real env file.
- `vim ...backend.docker.env` lets you put real lab values into the file.
- The real env file is ignored by `.dockerignore`, so Docker does not send it into the image build context.

Verify:

```bash
cat deployment/phase-3-docker/env/backend.docker.env
```

Why this step exists:

The backend container reads runtime settings from this file when it starts. The PostgreSQL migration command also reads this file.

## Step 9: Build Docker Images

Run from the repository root:

```bash
cd /opt/devops-launchboard/app-source
docker build -f deployment/phase-3-docker/Dockerfile.backend -t launchboard-backend:phase-3 .
docker build -f deployment/phase-3-docker/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-3 .
```

Command explanation:

- `cd /opt/devops-launchboard/app-source` moves to the repository root.
- `docker build` builds a Docker image.
- `-f deployment/phase-3-docker/Dockerfile.backend` tells Docker which Dockerfile to use.
- `-t launchboard-backend:phase-3` names and tags the backend image.
- The final `.` means the current folder is the Docker build context.
- `--build-arg VITE_API_URL=` passes an empty frontend API base URL, so the frontend uses relative API paths.

Verify:

```bash
docker images | grep launchboard
```

Expected:

```text
launchboard-backend    phase-3
launchboard-frontend   phase-3
```

Why this step exists:

Images are packaged application artifacts. A container is a running instance of an image.

Common issue:

If the backend build fails with an Alembic or dependency error, check this line in `Dockerfile.backend`:

```dockerfile
pip install --no-cache-dir ".[dev]"
```

This phase needs Alembic available inside the backend image because migrations run from the backend image.

Reference:

- Docker build docs: https://docs.docker.com/reference/cli/docker/buildx/build/

## Step 10: Push Docker Images To Docker Hub

Run this step from: EC2 server

Before you push, create two repositories in your own Docker Hub account.

Create these repositories from the Docker Hub website:

| Repository Name | Purpose | Visibility For Lab |
| --- | --- | --- |
| `launchboard-backend` | Stores the FastAPI backend image | Public or private |
| `launchboard-frontend` | Stores the Nginx frontend image | Public or private |

Use public repositories for student labs unless you have already taught private image pulls. Private repositories need authentication before pulling from another server.

Set your Docker Hub username as a variable. Replace `<dockerhub-username>` with your real Docker Hub username.

```bash
export DOCKERHUB_USERNAME=<dockerhub-username>
echo $DOCKERHUB_USERNAME
```

Example:

```bash
export DOCKERHUB_USERNAME=ashikdevops
echo $DOCKERHUB_USERNAME
```

Log in to Docker Hub:

```bash
docker login -u "$DOCKERHUB_USERNAME"
```

Command explanation:

- `export DOCKERHUB_USERNAME=<dockerhub-username>` stores your Docker Hub username in the current shell session.
- `docker login -u "$DOCKERHUB_USERNAME"` authenticates your Docker CLI with Docker Hub. Docker asks for your password or access token.
- Use a Docker Hub access token instead of your account password when possible.

Tag the local images for Docker Hub:

```bash
docker tag launchboard-backend:phase-3 "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"
docker tag launchboard-frontend:phase-3 "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"
```

Command explanation:

- `docker tag` does not rebuild the image. It creates another name for the same local image.
- `launchboard-backend:phase-3` is the local image name.
- `$DOCKERHUB_USERNAME/launchboard-backend:phase-3` is the Docker Hub image name.
- The part before `/` is your Docker Hub namespace.
- `phase-3` is the image tag. It marks this image as the Phase 3 version.

Push the images:

```bash
docker push "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"
docker push "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"
```

Command explanation:

- `docker push` uploads the tagged image layers to Docker Hub.
- Docker uploads only missing layers. If backend and frontend share some base layers, Docker reuses existing layers where possible.
- After this step, the images are available from Docker Hub using your username and repository names.

Verify pushed images locally:

```bash
docker images | grep "$DOCKERHUB_USERNAME/launchboard"
```

Expected:

```text
<dockerhub-username>/launchboard-backend    phase-3
<dockerhub-username>/launchboard-frontend   phase-3
```

Verify from Docker Hub:

```text
Docker Hub
Repositories
launchboard-backend
launchboard-frontend
Tags
phase-3
```

Important:

Do not put secrets inside Docker images. In this phase, the backend password stays in `deployment/phase-3-docker/env/backend.docker.env` and gets passed at container runtime using `--env-file`. That is the correct pattern for this lab.

If you open a new SSH terminal later, run this again before commands that use `$DOCKERHUB_USERNAME`:

```bash
export DOCKERHUB_USERNAME=<dockerhub-username>
```

Why this step exists:

Docker Hub is an image registry. A registry stores Docker images so another server, teammate, CI/CD pipeline, Docker Compose setup, or Kubernetes cluster can pull the same image without rebuilding it from source.

Reference:

- Docker Hub overview: https://docs.docker.com/docker-hub/
- Docker image tag: https://docs.docker.com/reference/cli/docker/image/tag/
- Docker image push: https://docs.docker.com/reference/cli/docker/image/push/

## Step 11: Create Docker Network And Volume

Run:

```bash
docker network inspect launchboard-net >/dev/null 2>&1 || docker network create launchboard-net
docker volume inspect launchboard-postgres-data >/dev/null 2>&1 || docker volume create launchboard-postgres-data
```

Command explanation:

- `docker network inspect launchboard-net >/dev/null 2>&1 || docker network create launchboard-net` checks if the network exists. If not, it creates it.
- `docker volume inspect launchboard-postgres-data >/dev/null 2>&1 || docker volume create launchboard-postgres-data` checks if the volume exists. If not, it creates it.

Verify:

```bash
docker network ls | grep launchboard-net
docker volume ls | grep launchboard-postgres-data
```

Why this step exists:

The Docker network lets containers reach each other by name, such as `launchboard-backend` and `launchboard-postgres`.

The Docker volume stores PostgreSQL data outside the container filesystem. If the PostgreSQL container is deleted and recreated, the data remains in the volume unless the volume is deleted.

Reference:

- Docker networking: https://docs.docker.com/engine/network/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/

## Step 12: Run PostgreSQL Container

Set one password variable first:

```bash
DB_PASSWORD='CHANGE_ME_STRONG_PASSWORD'
```

Replace `CHANGE_ME_STRONG_PASSWORD` with the same password used in `deployment/phase-3-docker/env/backend.docker.env`.

Example:

```bash
DB_PASSWORD='ashik12345'
```

Remove an old PostgreSQL container if you are rerunning the lab:

```bash
docker rm -f launchboard-postgres >/dev/null 2>&1 || true
```

Run PostgreSQL:

```bash
docker run -d \
  --name launchboard-postgres \
  --network launchboard-net \
  -e POSTGRES_DB=launchboard \
  -e POSTGRES_USER=launchboard_user \
  -e POSTGRES_PASSWORD="$DB_PASSWORD" \
  -v launchboard-postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:16-alpine
```

Command explanation:

- `docker rm -f launchboard-postgres >/dev/null 2>&1 || true` removes an old container with the same name if it exists.
- `docker run -d` starts a container in detached mode.
- `--name launchboard-postgres` gives the container a stable name. Other containers use this name as a hostname.
- `--network launchboard-net` connects the container to the app network.
- `POSTGRES_DB=launchboard` creates the app database during first startup.
- `POSTGRES_USER=launchboard_user` creates the app database user.
- `POSTGRES_PASSWORD="$DB_PASSWORD"` sets the password for the app database user.
- `-v launchboard-postgres-data:/var/lib/postgresql/data` stores database data in a Docker volume.
- `--restart unless-stopped` restarts the container after Docker or server restart unless you manually stopped it.
- `postgres:16-alpine` is the PostgreSQL image.

Verify:

```bash
docker ps --filter name=launchboard-postgres
docker logs launchboard-postgres --tail 50
```

Wait until PostgreSQL is ready:

```bash
until docker exec launchboard-postgres pg_isready -U launchboard_user -d launchboard; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done
```

Expected:

```text
/var/run/postgresql:5432 - accepting connections
```

Why this step exists:

The backend needs PostgreSQL before migrations and API startup. The wait command prevents students from running migrations before the database is ready.

Reference:

- PostgreSQL Docker image: https://hub.docker.com/_/postgres

## Step 13: Run Database Migrations

Run:

```bash
cd /opt/devops-launchboard/app-source
docker run --rm \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  "$DOCKERHUB_USERNAME/launchboard-backend:phase-3" \
  alembic upgrade head
```

Command explanation:

- `docker run --rm` starts a temporary container and removes it after the command finishes.
- `--network launchboard-net` lets the migration container reach `launchboard-postgres` by name.
- `--env-file ...backend.docker.env` loads `DATABASE_URL` and other backend settings.
- `$DOCKERHUB_USERNAME/launchboard-backend:phase-3` uses the backend image you pushed to Docker Hub. The image also exists locally after tagging, so Docker does not need to download it again on this same server.
- `alembic upgrade head` overrides the default backend startup command and runs migrations instead.

Expected output:

```text
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
INFO  [alembic.runtime.migration] Running upgrade  -> 20260515_0001, create launchboard tables
```

Verify tables:

```bash
docker exec -it launchboard-postgres psql -U launchboard_user -d launchboard -c "\dt"
```

Expected:

```text
alembic_version
deployments
services
```

Why this step exists:

Alembic creates or updates database tables. Without migrations, backend API routes that use the database may fail.

## Step 14: Run Backend Container

Remove an old backend container if you are rerunning the lab:

```bash
docker rm -f launchboard-backend >/dev/null 2>&1 || true
```

Run:

```bash
cd /opt/devops-launchboard/app-source
docker run -d \
  --name launchboard-backend \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  --restart unless-stopped \
  "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"
```

Command explanation:

- `docker rm -f launchboard-backend ...` removes an old backend container with the same name if one exists.
- `docker run -d` starts the backend container in the background.
- `--name launchboard-backend` gives the container a DNS name on the Docker network.
- `--network launchboard-net` connects the backend to the same network as PostgreSQL.
- `--env-file ...backend.docker.env` injects backend runtime configuration.
- `--restart unless-stopped` starts the backend again after Docker or EC2 restart.
- `$DOCKERHUB_USERNAME/launchboard-backend:phase-3` is the backend image to run. This proves the deployment uses a registry-ready image name.

Verify:

```bash
docker ps --filter name=launchboard-backend
docker logs launchboard-backend --tail 100
docker inspect --format='{{json .State.Health}}' launchboard-backend | jq
```

Wait for backend health:

```bash
until [ "$(docker inspect --format='{{.State.Health.Status}}' launchboard-backend)" = "healthy" ]; do
  echo "Waiting for backend health..."
  docker logs launchboard-backend --tail 10
  sleep 5
done
```

Expected:

```text
healthy
```

Why this step exists:

The backend is the API service. It stays private because it is not published with `-p`. Only containers on `launchboard-net` can reach it.

Important:

Do not publish backend port `8000` to the internet in this phase. The frontend Nginx container proxies requests to it internally.

## Step 15: Run Frontend Container

Check if EC2 port `80` is free:

```bash
sudo ss -tulpn | grep ':80 ' || echo "Port 80 is free"
```

If another service is already using port `80`, stop that service first. On a clean Phase 3 server this should usually be free.

Remove an old frontend container if you are rerunning the lab:

```bash
docker rm -f launchboard-frontend >/dev/null 2>&1 || true
```

Run:

```bash
docker run -d \
  --name launchboard-frontend \
  --network launchboard-net \
  -p 80:8080 \
  --restart unless-stopped \
  "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"
```

Command explanation:

- `docker rm -f launchboard-frontend ...` removes an old frontend container with the same name if one exists.
- `docker run -d` starts the frontend container in the background.
- `--name launchboard-frontend` gives the container a stable name.
- `--network launchboard-net` connects the frontend container to the backend container.
- `-p 80:8080` maps EC2 public port `80` to container port `8080`.
- `--restart unless-stopped` starts the frontend again after Docker or EC2 restart.
- `$DOCKERHUB_USERNAME/launchboard-frontend:phase-3` is the frontend image to run. This proves the deployment uses a registry-ready image name.

Port explanation:

```text
Browser -> EC2 public IP port 80 -> Docker port mapping -> frontend container port 8080
```

Verify:

```bash
docker ps --filter name=launchboard-frontend
docker logs launchboard-frontend --tail 100
docker inspect --format='{{json .State.Health}}' launchboard-frontend | jq
curl -I http://127.0.0.1
curl -s http://127.0.0.1/healthz
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Expected:

- `curl -I http://127.0.0.1` returns `HTTP/1.1 200 OK`.
- `/healthz` returns `ok` from frontend Nginx.
- `/health` returns backend health JSON.
- `/ready` returns backend readiness JSON.
- `/api/summary` returns application data JSON.

Why this step exists:

The frontend container is the public entry point. It serves static frontend files and forwards API requests to the backend container.

## Step 16: Verify From Browser

From your local machine, open:

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

If the browser does not load, test from the EC2 server first:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/healthz
curl -s http://127.0.0.1/api/summary | jq
```

Then check AWS security group:

```text
Port 80 must allow inbound traffic from 0.0.0.0/0.
```

Why this step exists:

Local EC2 tests prove the containers work on the server. Browser tests prove AWS networking and public access work.

## Docker Concepts Used In This Phase

### Image

An image is the packaged app template.

Example:

```text
launchboard-backend:phase-3
launchboard-frontend:phase-3
your-dockerhub-username/launchboard-backend:phase-3
your-dockerhub-username/launchboard-frontend:phase-3
postgres:16-alpine
```

### Image Registry

An image registry stores Docker images outside your server.

In this phase, Docker Hub is the registry.

Example:

```text
your-dockerhub-username/launchboard-backend:phase-3
your-dockerhub-username/launchboard-frontend:phase-3
```

Why it matters:

```text
Build image once
Push image to Docker Hub
Pull the same image from another server, CI/CD pipeline, or Kubernetes cluster
```

### Container

A container is a running instance of an image.

Example:

```text
launchboard-backend
launchboard-frontend
launchboard-postgres
```

### Network

A Docker network lets containers communicate by container name.

Example:

```text
launchboard-frontend -> launchboard-backend:8000
launchboard-backend -> launchboard-postgres:5432
```

### Volume

A Docker volume stores persistent data outside the container filesystem.

Example:

```text
launchboard-postgres-data -> /var/lib/postgresql/data
```

### Port mapping

Port mapping exposes a container port on the EC2 server.

Example:

```text
-p 80:8080
```

Meaning:

```text
EC2 port 80 -> frontend container port 8080
```

## Logs And Debugging

Show running containers:

```bash
docker ps
```

Show all containers, including stopped ones:

```bash
docker ps -a
```

Show logs:

```bash
docker logs launchboard-postgres --tail 100
docker logs launchboard-backend --tail 100
docker logs launchboard-frontend --tail 100
```

Follow logs live:

```bash
docker logs -f launchboard-backend
```

Inspect health:

```bash
docker inspect --format='{{json .State.Health}}' launchboard-backend | jq
docker inspect --format='{{json .State.Health}}' launchboard-frontend | jq
```

Inspect network:

```bash
docker network inspect launchboard-net | jq
```

Check PostgreSQL:

```bash
docker exec -it launchboard-postgres psql -U launchboard_user -d launchboard
```

Inside `psql`:

```sql
\dt
select current_database(), current_user;
\q
```

Check ports on EC2:

```bash
sudo ss -tulpn | grep ':80\|:8000\|:5432'
```

Expected:

- Port `80` should be published by Docker on the EC2 host.
- Port `8000` should not be published on the EC2 host.
- Port `5432` should not be published on the EC2 host.

Why this section exists:

Docker issues are usually visible in container status, logs, health checks, network settings, or port mappings.

## Common Problems And Fixes

### Problem 2: Docker command says permission denied

Check:

```bash
groups
```

If you do not see `docker`, log out and SSH back in:

```bash
exit
ssh -i <key-file>.pem ubuntu@<public-ip>
```

Why this happens:

`sudo usermod -aG docker ubuntu` updates group membership, but your current SSH session does not receive the new group list.

### Problem 3: Docker build sends too many files or includes secrets

Check:

```bash
ls -la /opt/devops-launchboard/app-source/.dockerignore
```

The `.dockerignore` file must be in the repository root.

Why this happens:

Docker only uses `.dockerignore` from the build context root. This phase uses `.` as the build context.

### Problem 4: Backend image builds but migration command fails with `alembic: not found`

Check `Dockerfile.backend`:

```dockerfile
pip install --no-cache-dir ".[dev]"
```

Why this happens:

Alembic may be listed under dev dependencies in the Python project. This phase runs migrations from the backend image, so Alembic must exist inside that image.

### Problem 5: Migration fails because database is not ready

Run:

```bash
docker logs launchboard-postgres --tail 100
docker exec launchboard-postgres pg_isready -U launchboard_user -d launchboard
```

Then wait:

```bash
until docker exec launchboard-postgres pg_isready -U launchboard_user -d launchboard; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done
```

### Problem 6: Backend cannot connect to database

Check env file:

```bash
cat deployment/phase-3-docker/env/backend.docker.env
```

Expected host inside `DATABASE_URL`:

```text
launchboard-postgres
```

Bad for this phase:

```text
127.0.0.1
localhost
```

Why:

Inside the backend container, `127.0.0.1` means the backend container itself, not the PostgreSQL container.

### Problem 7: Frontend shows but API fails

Check:

```bash
docker logs launchboard-frontend --tail 100
docker logs launchboard-backend --tail 100
curl -s http://127.0.0.1/api/summary | jq
```

Common causes:

```text
Backend container is not running.
Backend is unhealthy.
Frontend Nginx config points to the wrong backend name.
Containers are not on the same Docker network.
```

### Problem 8: Browser does not open the app

Check from EC2:

```bash
curl -I http://127.0.0.1
```

If this works on EC2 but not in your browser, check AWS security group:

```text
Port 80 must be open to 0.0.0.0/0.
```

If this fails on EC2, check whether frontend container is running:

```bash
docker ps --filter name=launchboard-frontend
docker logs launchboard-frontend --tail 100
```

### Problem 9: Port 80 is already allocated

Check:

```bash
sudo ss -tulpn | grep ':80 '
```

If another container uses port 80:

```bash
docker ps
```

Stop the old container or use a different port for practice:

```bash
docker run -d \
  --name launchboard-frontend \
  --network launchboard-net \
  -p 8080:8080 \
  --restart unless-stopped \
  launchboard-frontend:phase-3
```

Then open:

```text
http://YOUR_EC2_PUBLIC_IP:8080
```

For production, prefer domain-based routing through one Nginx or load balancer on ports `80` and `443`.

## Restart Commands

Restart containers:

```bash
docker restart launchboard-postgres
docker restart launchboard-backend
docker restart launchboard-frontend
```

Stop containers:

```bash
docker stop launchboard-frontend launchboard-backend launchboard-postgres
```

Start stopped containers:

```bash
docker start launchboard-postgres launchboard-backend launchboard-frontend
```

View restart policy:

```bash
docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' launchboard-backend
```

Why this section exists:

Students need to understand that containers are separate processes. Restarting one container does not automatically rebuild the image.

## Rebuild After Code Changes

If code changes are pulled from GitHub, rebuild images and recreate containers.

Run:

```bash
cd /opt/devops-launchboard/app-source
git pull origin main

docker build -f deployment/phase-3-docker/Dockerfile.backend -t launchboard-backend:phase-3 .
docker build -f deployment/phase-3-docker/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-3 .

export DOCKERHUB_USERNAME=<dockerhub-username>
docker tag launchboard-backend:phase-3 "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"
docker tag launchboard-frontend:phase-3 "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"
docker push "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"
docker push "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"

docker run --rm \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  "$DOCKERHUB_USERNAME/launchboard-backend:phase-3" \
  alembic upgrade head

docker rm -f launchboard-backend launchboard-frontend

docker run -d \
  --name launchboard-backend \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  --restart unless-stopped \
  "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"

docker run -d \
  --name launchboard-frontend \
  --network launchboard-net \
  -p 80:8080 \
  --restart unless-stopped \
  "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"
```

Why this step exists:

Docker containers do not automatically update when source code changes. You must rebuild the image and recreate the container.

## Rollback Plan

Use this when the app is broken and you need to restore an older Git version.

Stop and remove current app containers:

```bash
docker rm -f launchboard-frontend launchboard-backend || true
```

Restore a previous Git commit:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
```

Rebuild images:

```bash
docker build -f deployment/phase-3-docker/Dockerfile.backend -t launchboard-backend:phase-3 .
docker build -f deployment/phase-3-docker/Dockerfile.frontend --build-arg VITE_API_URL= -t launchboard-frontend:phase-3 .
```

Run migrations:

```bash
docker run --rm \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  "$DOCKERHUB_USERNAME/launchboard-backend:phase-3" \
  alembic upgrade head
```

Run containers again:

```bash
docker run -d \
  --name launchboard-backend \
  --network launchboard-net \
  --env-file deployment/phase-3-docker/env/backend.docker.env \
  --restart unless-stopped \
  "$DOCKERHUB_USERNAME/launchboard-backend:phase-3"

docker run -d \
  --name launchboard-frontend \
  --network launchboard-net \
  -p 80:8080 \
  --restart unless-stopped \
  "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3"
```

Verify:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/api/summary | jq
```

Why rollback exists:

Every production deployment needs a recovery path. Rollback prevents a broken deployment from staying public.

## Cleanup

Use cleanup when the lab is finished.

Stop and remove containers:

```bash
docker rm -f launchboard-frontend launchboard-backend launchboard-postgres || true
```

Remove network:

```bash
docker network rm launchboard-net || true
```

Remove volume:

```bash
docker volume rm launchboard-postgres-data || true
```

Important:

Removing the volume deletes PostgreSQL data for this lab.

Remove images:

```bash
docker rmi launchboard-backend:phase-3 launchboard-frontend:phase-3 || true
docker rmi "$DOCKERHUB_USERNAME/launchboard-backend:phase-3" "$DOCKERHUB_USERNAME/launchboard-frontend:phase-3" || true
```

Optional Docker cleanup:

```bash
docker system prune -f
```

Remove app source files:

```bash
sudo rm -rf /opt/devops-launchboard
```

Delete AWS resources:

```text
Terminate EC2 instance.
Delete unused EBS volumes.
Release unused Elastic IPs.
Delete snapshots.
Remove unused security groups.
Check AWS Billing dashboard.
Remove GitHub deploy key.
```

## Production Checklist

Before calling Phase 3 complete:

```text
[ ] EC2 security group exposes only 22, 80, and optional 443
[ ] SSH is restricted to your IP
[ ] Backend port 8000 is not public
[ ] PostgreSQL port 5432 is not public
[ ] Docker Engine installed from Docker's official repository
[ ] ubuntu user is in docker group
[ ] docker run hello-world works
[ ] GitHub SSH clone works
[ ] Project cloned from main branch
[ ] .dockerignore exists in repository root
[ ] Real backend env file created
[ ] Real backend env file is not included in Docker image build context
[ ] Backend Dockerfile created
[ ] Frontend Dockerfile created
[ ] Frontend Nginx config created
[ ] Backend image builds successfully
[ ] Frontend image builds successfully
[ ] Docker Hub repositories created
[ ] Docker Hub login works
[ ] Backend image tagged with Docker Hub username
[ ] Frontend image tagged with Docker Hub username
[ ] Backend image pushed to Docker Hub
[ ] Frontend image pushed to Docker Hub
[ ] Docker network created
[ ] Docker volume created
[ ] PostgreSQL container running
[ ] PostgreSQL readiness check passes
[ ] Alembic migrations completed
[ ] Backend container running
[ ] Backend container healthy
[ ] Frontend container running
[ ] Frontend container healthy
[ ] Local curl to http://127.0.0.1 works
[ ] /healthz works from frontend Nginx container
[ ] /health works through frontend Nginx container
[ ] /ready works through frontend Nginx container
[ ] /api/summary works through frontend Nginx container
[ ] Public frontend opens in browser
[ ] Logs checked
[ ] Rollback plan reviewed
[ ] Cleanup plan reviewed
```

## Required Files Created In This Phase

```text
/opt/devops-launchboard/app-source/.dockerignore

/opt/devops-launchboard/app-source/deployment/phase-3-docker/
+-- env/
|   +-- backend.docker.env.example
|   +-- backend.docker.env
|   +-- frontend.build.env.example
+-- Dockerfile.backend
+-- Dockerfile.frontend
+-- nginx-frontend.conf
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| AWS EC2 | https://docs.aws.amazon.com/ec2/ |
| Connect to Linux EC2 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html |
| Ubuntu package management | https://ubuntu.com/server/docs/how-to/software/package-management/index.html |
| Docker Engine Ubuntu install | https://docs.docker.com/engine/install/ubuntu/ |
| Docker post-install steps | https://docs.docker.com/engine/install/linux-postinstall/ |
| Dockerfile reference | https://docs.docker.com/reference/dockerfile/ |
| Docker build context | https://docs.docker.com/build/concepts/context/ |
| Docker build CLI | https://docs.docker.com/reference/cli/docker/buildx/build/ |
| Docker networking | https://docs.docker.com/engine/network/ |
| Docker volumes | https://docs.docker.com/engine/storage/volumes/ |
| PostgreSQL Docker image | https://hub.docker.com/_/postgres |
| FastAPI deployment | https://fastapi.tiangolo.com/deployment/ |
| Uvicorn deployment | https://www.uvicorn.org/deployment/ |
| Vite build docs | https://vite.dev/guide/build |
| Nginx docs | https://nginx.org/en/docs/ |
| Nginx proxy module | https://nginx.org/en/docs/http/ngx_http_proxy_module.html |
| AWS Budgets | https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html |

## What To Do Next

Move to:

```text
Phase 4: Docker Compose
```

Why:

Phase 3 teaches Docker manually. Phase 4 defines the same multi-container app in one Compose file so students do not need to type long `docker run` commands every time.
