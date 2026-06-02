# Phase 2: Bare-Metal EC2 Deployment

## Fresh Start Assumption

You do not need to complete any previous deployment phase before using this guide.

This phase starts from a clean AWS account or clean AWS lab environment and a fresh Ubuntu EC2 server.

This phase deploys the N-tier application manually on one EC2 instance:

- PostgreSQL runs on the EC2 server.
- FastAPI backend runs as a systemd service.
- React/Vite frontend is built into static files.
- Nginx serves the frontend and reverse proxies backend API routes.
- Optional Certbot can add HTTPS when you have a domain.

Students read this README from GitHub in the browser. Do not assume the deployment folder already exists on the EC2 server. Every file that must be created is shown inline immediately after the `vim` command that creates it.

No shell scripts are required in this phase.

## What This Phase Teaches

By completing this phase, students will learn:

- How to create an EC2 server.
- How to configure a safe security group.
- How to SSH into Ubuntu EC2.
- How to create a GitHub SSH key on the server.
- How to clone the project using SSH.
- How to install Python, Node.js, PostgreSQL, and Nginx manually.
- How to create a Linux service user.
- How to create a PostgreSQL app user and database.
- How to create backend and frontend environment files.
- How to install backend dependencies.
- How to run Alembic migrations.
- How to build the frontend for production.
- How to serve the frontend through Nginx.
- How to run FastAPI with systemd.
- How to proxy API traffic through Nginx.
- How to verify frontend, backend, database, logs, rollback, and cleanup.

## Architecture

```text
User Browser
  |
  | HTTP or HTTPS
  v
Nginx on EC2
  |
  +-- serves frontend static files from /var/www/devops-launchboard
  |
  +-- proxies /api, /health, and /ready to FastAPI
        |
        v
      FastAPI backend on 127.0.0.1:8000
        |
        v
      PostgreSQL on 127.0.0.1:5432
```

Service map:

| Service | Runs Where | Port | Public Access | Purpose |
| --- | --- | ---: | --- | --- |
| Nginx | EC2 | `80`, optional `443` | Yes | Public entry point |
| Frontend | Static files | Served by Nginx | Yes | Browser UI |
| Backend | systemd service | `8000` | No | FastAPI API |
| PostgreSQL | EC2 | `5432` | No | Database |

Important idea:

Users should reach the backend through Nginx only. Do not expose backend port `8000` publicly.

## Architecture Decision Guide

Use Phase 2 when:

- You want students to understand Linux deployment deeply.
- You want to learn users, folders, permissions, logs, systemd, Nginx, PostgreSQL, and ports.
- You are deploying a small app on one server.
- You want a manual foundation before Docker and Kubernetes.

Do not use Phase 2 when:

- You need automatic scaling.
- You need high availability.
- You need managed database backups.
- You need zero-downtime deployment.
- You want container orchestration.

Production note:

This is production-style for a single server, but not highly available. Real production should also consider managed PostgreSQL, automated backups, CI/CD, monitoring, TLS renewal, vulnerability scanning, and infrastructure as code.

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
| EC2 Name | `devops-launchboard-phase-2` |
| AMI | Ubuntu Server 24.04 LTS |
| Instance Type | `t3.micro` or `t3.small` |
| Storage | 20 GB gp3 |
| Key Pair | `devops-launchboard-key` |
| Security Group | `devops-launchboard-phase-2-sg` |
| SSH | Port `22`, your IP only |
| HTTP | Port `80`, anywhere |
| HTTPS | Port `443`, anywhere if using SSL |
| Backend | Port `8000`, do not expose publicly |
| PostgreSQL | Port `5432`, do not expose publicly |

Security group inbound rules:

| Type | Port | Source | Purpose |
| --- | ---: | --- | --- |
| SSH | `22` | Your IP only | Server access |
| HTTP | `80` | `0.0.0.0/0` | Public app |
| HTTPS | `443` | `0.0.0.0/0` | Public app with SSL |

Do not open:

```text
8000
5432
5173
```

Why:

- `8000` is private backend traffic.
- `5432` is private database traffic.
- `5173` is a Vite development server port and should not be used in production.

## Deployment Plan

You will follow this flow:

1. Create EC2 server.
2. SSH into EC2.
3. Install base tools.
4. Install Python, Node.js, PostgreSQL, and Nginx.
5. Create Linux service user.
6. Create GitHub SSH key on EC2.
7. Clone the project from `main`.
8. Create PostgreSQL user and database.
9. Create backend environment file.
10. Create frontend production environment file.
11. Install backend dependencies.
12. Run Alembic migrations.
13. Test backend manually.
14. Build frontend.
15. Publish frontend to Nginx web root.
16. Create systemd service files.
17. Start backend through systemd.
18. Create Nginx config.
19. Verify app through public IP.
20. Optional domain and HTTPS.
21. Rollback.
22. Cleanup.

## Step 1: Create EC2 Server

Run this step from: AWS Console

Create an EC2 instance with:

| Field | Value |
| --- | --- |
| Name | `devops-launchboard-phase-2` |
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

The application needs a Linux server. Security groups control which traffic can reach that server.

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

SSH gives you terminal access to install tools, clone code, configure services, and inspect logs.

## Step 3: Update Server And Install Base Tools

Run this command from: EC2 server

```bash
cd ~
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl wget vim jq tree unzip ca-certificates gnupg lsb-release rsync software-properties-common
```

Verify:

```bash
git --version
curl --version
jq --version
tree --version
rsync --version
```

Why this step exists:

Fresh servers have old package metadata and may be missing tools needed for deployment.

Reference:

- Ubuntu package management: https://ubuntu.com/server/docs/package-management

## Step 4: Install Python, PostgreSQL, Nginx, And Node.js 22

Install Python, PostgreSQL, and Nginx:

```bash
sudo apt install -y python3 python3-venv python3-pip postgresql postgresql-contrib nginx
```

Install Node.js 22 using the NodeSource apt repository:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update
sudo apt install -y nodejs
```

Enable services:

```bash
sudo systemctl enable postgresql
sudo systemctl start postgresql
sudo systemctl enable nginx
sudo systemctl start nginx
```

Verify:

```bash
python3 --version
node --version
npm --version
psql --version
systemctl status postgresql --no-pager
systemctl status nginx --no-pager
```

Why this step exists:

Python runs the backend. Node builds the frontend. PostgreSQL stores data. Nginx is the public web server and reverse proxy.

Reference:

- NodeSource distributions: https://github.com/nodesource/distributions
- PostgreSQL documentation: https://www.postgresql.org/docs/
- Ubuntu Nginx guide: https://ubuntu.com/tutorials/install-and-configure-nginx

## Step 5: Create Linux Service User And Folders

Run:

```bash
sudo useradd --system --create-home --home-dir /opt/devops-launchboard --shell /bin/bash launchboard || true
sudo mkdir -p /opt/devops-launchboard/app-source
sudo mkdir -p /etc/devops-launchboard
sudo mkdir -p /var/www/devops-launchboard
sudo chown -R ubuntu:ubuntu /opt/devops-launchboard/app-source
sudo chown -R launchboard:launchboard /etc/devops-launchboard
sudo chown -R www-data:www-data /var/www/devops-launchboard
```

Verify:

```bash
id launchboard
ls -ld /opt/devops-launchboard /opt/devops-launchboard/app-source /etc/devops-launchboard /var/www/devops-launchboard
```

Why this step exists:

The app should not run as root. A dedicated `launchboard` user limits what the backend process can access.

Folder purpose:

| Folder | Purpose |
| --- | --- |
| `/opt/devops-launchboard/app-source` | Application source code |
| `/etc/devops-launchboard` | Runtime environment files |
| `/var/www/devops-launchboard` | Built frontend static files |

## Step 6: Create GitHub SSH Key On EC2

Run:

```bash
cd ~
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -C "devops-launchboard-phase-2-ec2" -f ~/.ssh/devops_launchboard_github_key
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
| Title | `devops-launchboard-phase-2-ec2` |
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

The EC2 server needs GitHub access to clone the app source code.

Reference:

- GitHub SSH docs: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

## Step 7: Clone The Project

Run:

```bash
cd /opt/devops-launchboard/app-source
git clone git@github.com:ashraful2430/N-tier-application.git .
git branch --show-current
tree -L 2 -a
```

Expected branch:

```text
main
```

Set ownership:

```bash
sudo chown -R launchboard:launchboard /opt/devops-launchboard
```

Why this step exists:

The app source must be on the server before dependencies can be installed or services started.

## Step 8: Create PostgreSQL User And Database

Run:

```bash
sudo -u postgres psql
```

Inside `psql`, paste this. Replace `CHANGE_ME_STRONG_PASSWORD` with a strong password and remember it for the backend env file:

```sql
CREATE USER launchboard_user WITH PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
CREATE DATABASE launchboard OWNER launchboard_user;
GRANT ALL PRIVILEGES ON DATABASE launchboard TO launchboard_user;
\q
```

Verify:

```bash
psql "postgresql://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard" -c "select current_database(), current_user;"
```

Why this step exists:

The app needs its own database and database user. Using a dedicated user is safer than connecting as `postgres`.

## Step 9: Create Backend Environment File

Run:

```bash
sudo vim /etc/devops-launchboard/backend.env
```

Paste:

```env
APP_NAME=DevOps LaunchBoard API
APP_ENV=production
DATABASE_URL=postgresql+asyncpg://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard
CORS_ORIGINS=http://YOUR_EC2_PUBLIC_IP
SEED_DEMO_DATA=true
```

Replace:

```text
CHANGE_ME_STRONG_PASSWORD
YOUR_EC2_PUBLIC_IP
```

Set permissions:

```bash
sudo chown launchboard:launchboard /etc/devops-launchboard/backend.env
sudo chmod 600 /etc/devops-launchboard/backend.env
```

Why this file exists:

systemd loads this file before starting the backend. It keeps production runtime settings outside the Git repository.

Line explanation:

- `APP_NAME` names the FastAPI app.
- `APP_ENV=production` labels this as a production-style runtime.
- `DATABASE_URL` tells SQLAlchemy where PostgreSQL is.
- `CORS_ORIGINS` allows the browser origin served by Nginx.
- `SEED_DEMO_DATA=true` loads demo data on startup if the database is empty.

## Step 10: Create Frontend Production Environment File

Run:

```bash
sudo -u launchboard vim /opt/devops-launchboard/app-source/frontend/.env.production
```

Paste:

```env
VITE_API_URL=http://YOUR_EC2_PUBLIC_IP
```

Replace:

```text
YOUR_EC2_PUBLIC_IP
```

Why this file exists:

Vite reads `.env.production` during `npm run build`. The browser bundle needs the public backend base URL. Since Nginx proxies backend paths on the same host, this value should be the public app origin.

Line explanation:

- `VITE_API_URL` is the base URL used by frontend browser code before adding paths like `/api/summary`.

Reference:

- Vite env variables: https://vite.dev/guide/env-and-mode

## Step 11: Install Backend Dependencies

Run:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && python3 -m venv .venv'
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && . .venv/bin/activate && python -m pip install --upgrade pip'
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && . .venv/bin/activate && pip install -e ".[dev]"'
```

Verify:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && . .venv/bin/activate && python --version && pip list'
```

Why this step exists:

The backend needs a Python virtual environment and dependencies before it can start.

## Step 12: Run Database Migrations

Run:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && set -a && . /etc/devops-launchboard/backend.env && set +a && . .venv/bin/activate && alembic upgrade head'
```

Verify:

```bash
psql "postgresql://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard" -c "\dt"
```

Why this step exists:

Alembic creates the database tables. Without migrations, API routes that use the database can fail.

Reference:

- Alembic tutorial: https://alembic.sqlalchemy.org/en/latest/tutorial.html

## Step 13: Test Backend Manually

Run:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && set -a && . /etc/devops-launchboard/backend.env && set +a && . .venv/bin/activate && uvicorn app.main:app --host 127.0.0.1 --port 8000'
```

Open a second SSH terminal and test:

```bash
curl -s http://127.0.0.1:8000/health | jq
curl -s http://127.0.0.1:8000/ready | jq
curl -s http://127.0.0.1:8000/api/summary | jq
```

Stop the manual backend:

```text
Press CTRL + C in the first terminal.
```

Why this step exists:

Manual startup shows direct errors before systemd is introduced. This prevents students from blaming systemd for app configuration problems.

Reference:

- Uvicorn deployment: https://www.uvicorn.org/deployment/
- FastAPI deployment: https://fastapi.tiangolo.com/deployment/

## Step 14: Build Frontend

Run:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/frontend && npm install'
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/frontend && npm run build'
```

Verify:

```bash
ls -la /opt/devops-launchboard/app-source/frontend/dist
test -f /opt/devops-launchboard/app-source/frontend/dist/index.html && echo "Frontend build exists"
```

Why this step exists:

Production Nginx serves static files from a build output. It does not run the Vite development server.

## Step 15: Publish Frontend To Nginx Web Root

Run:

```bash
sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
```

Verify:

```bash
ls -la /var/www/devops-launchboard
test -f /var/www/devops-launchboard/index.html && echo "Frontend published"
```

Why this step exists:

Nginx serves files from `/var/www/devops-launchboard`. The build must be copied there before users can open the UI.

## Step 16: Create systemd Service Files

Create backend service:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-2-bare-metal/systemd
vim deployment/phase-2-bare-metal/systemd/launchboard-backend.service
```

Paste:

```ini
[Unit]
Description=DevOps LaunchBoard Backend API
Wants=network-online.target postgresql.service
After=network-online.target postgresql.service

[Service]
Type=simple
User=launchboard
Group=launchboard
WorkingDirectory=/opt/devops-launchboard/app-source/backend
EnvironmentFile=/etc/devops-launchboard/backend.env
ExecStart=/opt/devops-launchboard/app-source/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=always
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30
KillSignal=SIGTERM
StandardOutput=journal
StandardError=journal
SyslogIdentifier=launchboard-backend
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/devops-launchboard/app-source/backend

[Install]
WantedBy=multi-user.target
```

Backend service explanation:

- `[Unit]` describes the service and startup ordering.
- `Wants=network-online.target postgresql.service` asks for network and PostgreSQL.
- `After=network-online.target postgresql.service` starts backend after those services.
- `User=launchboard` runs the API as the app user, not root.
- `WorkingDirectory` points to the backend folder.
- `EnvironmentFile` loads production env values.
- `ExecStart` starts Uvicorn on private localhost port `8000`.
- `Restart=always` restarts the backend after crashes.
- `StandardOutput` and `StandardError` send logs to journald.
- `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem`, and `ProtectHome` reduce process permissions.
- `ReadWritePaths` allows writes only where the backend may need them.

Create frontend validation service:

```bash
vim deployment/phase-2-bare-metal/systemd/launchboard-frontend.service
```

Paste:

```ini
[Unit]
Description=DevOps LaunchBoard Frontend Static Files
After=nginx.service
Wants=nginx.service

[Service]
Type=oneshot
ExecStart=/usr/bin/test -f /var/www/devops-launchboard/index.html
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Frontend service explanation:

- Nginx serves the frontend, so the frontend does not need a long-running Node process.
- This service validates that the built frontend file exists.
- `RemainAfterExit=yes` keeps the validation unit in an active state after the check succeeds.

Install services:

```bash
sudo cp deployment/phase-2-bare-metal/systemd/launchboard-backend.service /etc/systemd/system/launchboard-backend.service
sudo cp deployment/phase-2-bare-metal/systemd/launchboard-frontend.service /etc/systemd/system/launchboard-frontend.service
sudo systemctl daemon-reload
sudo systemctl enable launchboard-backend
sudo systemctl enable launchboard-frontend
sudo systemctl restart launchboard-backend
sudo systemctl restart launchboard-frontend
```

Verify:

```bash
sudo systemctl status launchboard-backend --no-pager
sudo systemctl status launchboard-frontend --no-pager
curl -s http://127.0.0.1:8000/health | jq
```

Reference:

- systemd service units: https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html
- systemctl: https://www.freedesktop.org/software/systemd/man/latest/systemctl.html

## Step 17: Create Nginx Config

Run:

```bash
cd /opt/devops-launchboard/app-source
mkdir -p deployment/phase-2-bare-metal/nginx
vim deployment/phase-2-bare-metal/nginx/default.conf
```

Paste:

```nginx
server {
    listen 80;
    server_name _;

    root /var/www/devops-launchboard;
    index index.html;

    client_max_body_size 10M;

    location = /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 "ok";
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /health {
        proxy_pass http://127.0.0.1:8000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /ready {
        proxy_pass http://127.0.0.1:8000/ready;
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

- `listen 80` accepts public HTTP traffic.
- `server_name _` works for IP-based access before a domain is configured.
- `root /var/www/devops-launchboard` points to built frontend files.
- `client_max_body_size 10M` allows reasonable request bodies.
- `/healthz` gives a simple Nginx-only health endpoint.
- `/api/` proxies API routes to FastAPI on `127.0.0.1:8000`.
- `/health` and `/ready` proxy backend health checks.
- Proxy headers preserve original host, client IP, and protocol.
- `try_files $uri $uri/ /index.html` supports browser-side frontend routes.

Install config:

```bash
sudo cp deployment/phase-2-bare-metal/nginx/default.conf /etc/nginx/sites-available/devops-launchboard
sudo ln -sf /etc/nginx/sites-available/devops-launchboard /etc/nginx/sites-enabled/devops-launchboard
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

Verify:

```bash
curl -I http://127.0.0.1
curl -s http://127.0.0.1/health | jq
curl -s http://127.0.0.1/ready | jq
curl -s http://127.0.0.1/api/summary | jq
```

Reference:

- Nginx beginner guide: https://nginx.org/en/docs/beginners_guide.html
- Nginx proxy module: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- FastAPI behind proxy: https://fastapi.tiangolo.com/advanced/behind-a-proxy/

## Step 18: Verify Public App

From your local machine:

```bash
curl -I http://YOUR_EC2_PUBLIC_IP
curl -s http://YOUR_EC2_PUBLIC_IP/health
curl -s http://YOUR_EC2_PUBLIC_IP/ready
```

Open in browser:

```text
http://YOUR_EC2_PUBLIC_IP
```

Expected:

```text
Frontend loads.
Backend health returns ok.
Backend readiness returns ready.
API data appears in the frontend.
```

## Step 19: Optional Domain Setup

If you own a domain, create this DNS record:

| Type | Name | Value |
| --- | --- | --- |
| A | `launchboard` | `YOUR_EC2_PUBLIC_IP` |

Example:

```text
launchboard.example.com -> YOUR_EC2_PUBLIC_IP
```

Update backend env:

```bash
sudo vim /etc/devops-launchboard/backend.env
```

Set:

```env
CORS_ORIGINS=http://launchboard.example.com
```

Update frontend env:

```bash
sudo -u launchboard vim /opt/devops-launchboard/app-source/frontend/.env.production
```

Set:

```env
VITE_API_URL=http://launchboard.example.com
```

Rebuild and publish:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/frontend && npm run build'
sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
sudo systemctl restart launchboard-backend
sudo systemctl reload nginx
```

Why this step exists:

Domains are easier for users than IP addresses and are required for trusted HTTPS certificates.

## Step 20: Optional HTTPS With Certbot

Only run this after DNS points to the EC2 public IP.

Replace:

- `launchboard.example.com`
- `you@example.com`

```bash
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d launchboard.example.com --non-interactive --agree-tos -m you@example.com --redirect
sudo nginx -t
sudo systemctl reload nginx
```

After HTTPS, update env values:

```bash
sudo vim /etc/devops-launchboard/backend.env
```

Set:

```env
CORS_ORIGINS=https://launchboard.example.com
```

Update frontend:

```bash
sudo -u launchboard vim /opt/devops-launchboard/app-source/frontend/.env.production
```

Set:

```env
VITE_API_URL=https://launchboard.example.com
```

Rebuild and restart:

```bash
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/frontend && npm run build'
sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
sudo systemctl restart launchboard-backend
sudo systemctl reload nginx
```

Verify:

```bash
curl -I https://launchboard.example.com
curl -s https://launchboard.example.com/health
```

Reference:

- Certbot documentation: https://eff-certbot.readthedocs.io/en/stable/
- Let's Encrypt documentation: https://letsencrypt.org/docs/

## Logs And Debugging

Backend status:

```bash
sudo systemctl status launchboard-backend --no-pager
sudo journalctl -u launchboard-backend -n 100 --no-pager
sudo journalctl -u launchboard-backend -f
```

Nginx logs:

```bash
sudo tail -n 100 /var/log/nginx/error.log
sudo tail -n 100 /var/log/nginx/access.log
```

PostgreSQL:

```bash
sudo systemctl status postgresql --no-pager
sudo -u postgres psql -c "\l"
```

Ports:

```bash
sudo ss -tulpn | grep ':80\|:8000\|:5432'
```

## Rollback Plan

Use this when the app is broken and you need to stop public serving quickly.

```bash
sudo systemctl stop launchboard-backend || true
sudo systemctl disable launchboard-backend || true
sudo rm -f /etc/nginx/sites-enabled/devops-launchboard

if [ -f /etc/nginx/sites-available/default ]; then
  sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi

sudo nginx -t
sudo systemctl reload nginx
```

Restore a previous Git version:

```bash
cd /opt/devops-launchboard/app-source
git log --oneline -5
git checkout PREVIOUS_COMMIT
sudo chown -R launchboard:launchboard /opt/devops-launchboard

sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && . .venv/bin/activate && pip install -e ".[dev]"'
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/backend && set -a && . /etc/devops-launchboard/backend.env && set +a && . .venv/bin/activate && alembic upgrade head'
sudo -u launchboard bash -lc 'cd /opt/devops-launchboard/app-source/frontend && npm install && npm run build'

sudo rsync -av --delete /opt/devops-launchboard/app-source/frontend/dist/ /var/www/devops-launchboard/
sudo chown -R www-data:www-data /var/www/devops-launchboard
sudo systemctl restart launchboard-backend
sudo systemctl reload nginx
```

Why rollback exists:

Every production deployment needs a recovery path. Rollback prevents a broken deployment from staying public.

## Troubleshooting

### Problem 1: Cannot SSH

Check:

```bash
ssh -i key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Common causes:

```text
Wrong key.
Bad key permissions.
Security group does not allow port 22 from your IP.
EC2 public IP changed.
```

### Problem 2: Backend Service Fails

Check:

```bash
sudo journalctl -u launchboard-backend -n 100 --no-pager
cat /etc/devops-launchboard/backend.env
sudo systemctl status postgresql --no-pager
```

Common causes:

```text
Wrong DATABASE_URL.
PostgreSQL is stopped.
Migrations were not run.
Virtual environment is missing dependencies.
```

### Problem 3: Frontend Loads But API Fails

Check:

```bash
cat /opt/devops-launchboard/app-source/frontend/.env.production
curl -s http://127.0.0.1:8000/health
curl -s http://127.0.0.1:8000/api/summary
curl -s http://127.0.0.1/api/summary
```

Common causes:

```text
Frontend was built with wrong VITE_API_URL.
Backend service is down.
Nginx proxy config is wrong.
CORS_ORIGINS does not match browser origin.
```

### Problem 4: Nginx 502 Bad Gateway

Check:

```bash
sudo systemctl status launchboard-backend --no-pager
sudo ss -tulpn | grep :8000
sudo nginx -t
```

Common causes:

```text
Backend is not running.
Backend listens on the wrong port.
Nginx proxy points to the wrong port.
```

### Problem 5: Readiness Fails

Check:

```bash
curl -s http://127.0.0.1:8000/ready | jq
sudo systemctl status postgresql --no-pager
psql "postgresql://launchboard_user:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/launchboard" -c "select 1;"
```

Common causes:

```text
Database user missing.
Database missing.
Wrong password.
PostgreSQL stopped.
```

## Cleanup

Stop services:

```bash
sudo systemctl stop launchboard-backend || true
sudo systemctl stop launchboard-frontend || true
sudo systemctl stop nginx || true
```

Remove app files:

```bash
sudo rm -rf /opt/devops-launchboard
sudo rm -rf /var/www/devops-launchboard
sudo rm -rf /etc/devops-launchboard
sudo rm -f /etc/systemd/system/launchboard-backend.service
sudo rm -f /etc/systemd/system/launchboard-frontend.service
sudo rm -f /etc/nginx/sites-enabled/devops-launchboard
sudo rm -f /etc/nginx/sites-available/devops-launchboard
sudo systemctl daemon-reload
```

Remove database:

```bash
sudo -u postgres psql
```

Inside `psql`:

```sql
DROP DATABASE IF EXISTS launchboard;
DROP USER IF EXISTS launchboard_user;
\q
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

Before calling Phase 2 complete:

```text
[ ] EC2 security group exposes only 22, 80, and optional 443
[ ] SSH is restricted to your IP
[ ] Backend port 8000 is not public
[ ] PostgreSQL port 5432 is not public
[ ] GitHub SSH clone works
[ ] Project cloned from main branch
[ ] launchboard Linux user exists
[ ] PostgreSQL app user and database created
[ ] /etc/devops-launchboard/backend.env created
[ ] frontend/.env.production created
[ ] Backend dependencies installed
[ ] Alembic migrations completed
[ ] Backend works manually
[ ] Frontend build completed
[ ] Frontend copied to /var/www/devops-launchboard
[ ] systemd backend service active
[ ] frontend validation service active
[ ] Nginx config test passes
[ ] Public frontend opens
[ ] /health works through Nginx
[ ] /ready works through Nginx
[ ] /api/summary works through Nginx
[ ] Logs checked
[ ] Rollback plan reviewed
[ ] Cleanup plan reviewed
```

## Required Files Created In This Phase

```text
deployment/phase-2-bare-metal/
+-- env/
|   +-- backend.env.example
|   +-- frontend.env.example
+-- nginx/
|   +-- default.conf
+-- systemd/
    +-- launchboard-backend.service
    +-- launchboard-frontend.service
```

## Reference Documentation

| Topic | Official Link |
| --- | --- |
| AWS EC2 | https://docs.aws.amazon.com/ec2/ |
| Connect to Linux EC2 | https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html |
| Ubuntu package management | https://ubuntu.com/server/docs/package-management |
| NodeSource Node.js packages | https://github.com/nodesource/distributions |
| PostgreSQL docs | https://www.postgresql.org/docs/ |
| FastAPI deployment | https://fastapi.tiangolo.com/deployment/ |
| FastAPI behind proxy | https://fastapi.tiangolo.com/advanced/behind-a-proxy/ |
| Uvicorn deployment | https://www.uvicorn.org/deployment/ |
| systemd service docs | https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html |
| Nginx docs | https://nginx.org/en/docs/ |
| Vite env variables | https://vite.dev/guide/env-and-mode |
| Certbot docs | https://eff-certbot.readthedocs.io/en/stable/ |

## What To Do Next

Move to:

```text
Phase 3: Docker Images
```

Why:

Phase 2 teaches raw Linux deployment. Phase 3 packages the same app into production Docker images so runtime dependencies become repeatable.
